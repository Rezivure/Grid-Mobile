import Foundation
import os.log

#if canImport(MatrixRustSDK)
import MatrixRustSDK
#endif

private let decryptionLog = OSLog(subsystem: "app.mygrid.grid", category: "NSE.Decrypt")

/// Wraps `matrix-rust-sdk`'s `NotificationClient` for use inside the NSE.
///
/// **Status**: skeleton. The Swift Package dependency on `MatrixRustSDK`
/// (https://github.com/element-hq/matrix-rust-components-swift) must be added
/// to the `GridNotificationService` target before this file does anything
/// meaningful. Until the dep is wired, `canImport(MatrixRustSDK)` is false
/// and `fetchAndDecrypt` throws `.sdkNotLinked` — the existing HTTP path in
/// `NotificationService.swift` then takes over and behavior is unchanged.
///
/// **Architecture choice (Pattern A)**: Grid's main app uses
/// **matrix-dart-sdk**, not matrix-rust-sdk, so the NSE cannot share a
/// crypto store with the main app — store formats and olm identities differ.
/// Instead the NSE manages its own rust-sdk session, scoped to a separate
/// device, with its store at:
///
///     containerURL(forSecurityApplicationGroupIdentifier: "group.app.mygrid.grid")
///       .appendingPathComponent("nse-crypto-store")
///
/// The main app (matrix-dart-sdk) is configured with
/// `shareKeysWith: ShareKeysWith.all` (`lib/main.dart`), so once this NSE
/// device is verified — either through cross-signing trust passed via the
/// AppGroupBridge or by the user manually verifying it — megolm keys flow to
/// it via `m.room_key` to-device events on the main app's next sync.
///
/// **Ownership**: short-lived. Construct, call `fetchAndDecrypt`, release.
/// The on-disk SQLite store the rust-sdk maintains is shared across NSE
/// launches, but the in-memory `Client` is not.
final class NotificationDecryptionClient {

    /// Minimal projection of a decrypted Matrix event — only the fields the
    /// classifier needs. This is decoupled from `MatrixEvent` (the HTTP-path
    /// model) so the rust-sdk's evolving FFI types don't leak into the
    /// classifier and so we don't have to round-trip through JSON.
    struct DecryptedEvent {
        let eventID: String
        let roomID: String
        let senderID: String?
        let senderDisplayName: String?
        let eventType: String        // e.g. "m.room.member"
        let stateKey: String?
        let membership: String?      // "invite" | "join" | "leave" | ...
        let prevMembership: String?  // from unsigned.prev_content
        let isDirectInvite: Bool?    // m.room.member is_direct flag
        let roomDisplayName: String? // resolved by rust-sdk from room state
    }

    enum DecryptionError: Error {
        case sdkNotLinked          // MatrixRustSDK SPM dep not added yet
        case missingCredentials
        case clientBuildFailed(String)
        case sessionRestoreFailed(String)
        case notificationFetchFailed(String)
        case eventNotFound
    }

    private let homeserverURL: String
    private let accessToken: String
    private let userID: String
    private let deviceID: String?

    /// App-group-scoped store directory. Isolated from the main app's
    /// matrix-dart-sdk SQLite database; shared only with future NSE launches.
    private let storeDirectory: URL

    init?(storage: SharedStorage) {
        guard let hs = storage.homeserverURL,
              let tok = storage.accessToken,
              let uid = storage.userID else {
            return nil
        }
        self.homeserverURL = hs
        self.accessToken = tok
        self.userID = uid
        self.deviceID = storage.deviceID

        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedStorage.appGroupID
        ) else {
            return nil
        }
        self.storeDirectory = container.appendingPathComponent("nse-crypto-store", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: self.storeDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Fetch and (if encrypted) decrypt a single event.
    ///
    /// Internally the rust-sdk falls through:
    ///   1. Short-lived sliding sync (`get_notification_with_sliding_sync`)
    ///   2. `/context` query (`get_notification_with_context`)
    ///
    /// Either path uses the on-disk olm/megolm store to attempt decryption.
    /// If keys haven't arrived yet (cold launch, no key-share message yet),
    /// this throws and the caller falls back to the HTTP path.
    func fetchAndDecrypt(
        roomID: String,
        eventID: String
    ) async throws -> DecryptedEvent {
        #if canImport(MatrixRustSDK)
        return try await fetchAndDecryptImpl(roomID: roomID, eventID: eventID)
        #else
        os_log(
            "MatrixRustSDK not linked — skip decryption path",
            log: decryptionLog, type: .info
        )
        throw DecryptionError.sdkNotLinked
        #endif
    }

    // MARK: - Real implementation (only compiled when SPM dep is present)

    #if canImport(MatrixRustSDK)
    private func fetchAndDecryptImpl(
        roomID: String,
        eventID: String
    ) async throws -> DecryptedEvent {
        os_log("building rust-sdk client", log: decryptionLog, type: .info)

        let dataPath = storeDirectory.path
        let cachePath = storeDirectory
            .appendingPathComponent("cache", isDirectory: true)
            .path
        try? FileManager.default.createDirectory(
            atPath: cachePath,
            withIntermediateDirectories: true
        )

        let client: Client
        do {
            client = try await ClientBuilder()
                .sessionPaths(dataPath: dataPath, cachePath: cachePath)
                .homeserverUrl(url: homeserverURL)
                .build()
        } catch {
            throw DecryptionError.clientBuildFailed(String(describing: error))
        }

        do {
            try await client.restoreSession(session: Session(
                accessToken: accessToken,
                refreshToken: nil,
                userId: userID,
                deviceId: deviceID ?? "",
                homeserverUrl: homeserverURL,
                oidcData: nil,
                slidingSyncVersion: .native
            ))
        } catch {
            throw DecryptionError.sessionRestoreFailed(String(describing: error))
        }

        os_log("session restored, fetching notification %{public}@/%{public}@",
               log: decryptionLog, type: .info, roomID, eventID)

        let notifClient: NotificationClient
        do {
            // The NSE is a *separate* OS process from the main Grid app, so
            // .multipleProcesses is the correct setup. .singleProcess is for
            // when the same process owns both a SyncService and the
            // NotificationClient.
            notifClient = try await client.notificationClient(
                processSetup: .multipleProcesses
            )
        } catch {
            throw DecryptionError.notificationFetchFailed(
                "notificationClient(): \(error)"
            )
        }

        let status: NotificationStatus
        do {
            status = try await notifClient.getNotification(
                roomId: roomID,
                eventId: eventID
            )
        } catch {
            throw DecryptionError.notificationFetchFailed(String(describing: error))
        }

        // `NotificationStatus` is an enum of {event, eventFilteredOut, eventNotFound}.
        // Pattern-match each known case; on filtered/not-found we throw so the
        // HTTP fallback path runs.
        switch status {
        case .event(let item):
            os_log("notification decrypted; mapping to DecryptedEvent",
                   log: decryptionLog, type: .info)
            return mapNotificationItem(item, roomID: roomID, eventID: eventID)
        @unknown default:
            throw DecryptionError.eventNotFound
        }
    }

    /// Translate the rust-sdk `NotificationItem` into our classifier-friendly
    /// `DecryptedEvent`. Field accessors below assume the
    /// `matrix-rust-components-swift` API surface circa version `26.04.x` —
    /// adjust if the SPM-pinned version diverges.
    private func mapNotificationItem(
        _ item: NotificationItem,
        roomID: String,
        eventID: String
    ) -> DecryptedEvent {
        // Layout (matrix-rust-components-swift ~26.04.x):
        //   NotificationItem
        //     .event:       NotificationEvent  (enum: .timeline(TimelineEvent) | .invite(sender))
        //     .senderInfo:  NotificationSenderInfo  (.displayName, .avatarUrl)
        //     .roomInfo:    NotificationRoomInfo    (.displayName, .isDirect, ...)
        //     .isNoisy:     Bool?
        //
        // For an *invite* the wrapping NotificationEvent case is `.invite(...)`
        // and there's no full TimelineEvent. For other events, .timeline
        // carries the decrypted body. Under Grid's allowlist policy the only
        // events we expect here are invite-state members on the user.
        let senderDisplay = item.senderInfo.displayName
        let roomDisplay = item.roomInfo.displayName
        let roomIsDirect = item.roomInfo.isDirect

        let eventType: String
        let membership: String?

        switch item.event {
        case .invite:
            eventType = "m.room.member"
            membership = "invite"
        case .timeline:
            // Allowlist push rules currently keep encrypted messages from
            // reaching us at all; if one slips through, treat as generic
            // message and let the classifier suppress.
            eventType = "m.room.message"
            membership = nil
        @unknown default:
            eventType = "m.room.message"
            membership = nil
        }

        return DecryptedEvent(
            eventID: eventID,
            roomID: roomID,
            senderID: nil,
            senderDisplayName: senderDisplay,
            eventType: eventType,
            stateKey: nil,
            membership: membership,
            prevMembership: nil,
            isDirectInvite: roomIsDirect,
            roomDisplayName: roomDisplay
        )
    }
    #endif
}
