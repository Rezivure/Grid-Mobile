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
        // -----------------------------------------------------------------
        // TODO(phase-3-followup): wire actual rust-sdk APIs.
        //
        // Pseudocode mirroring Element-X iOS NSE flow (NSEUserSession.swift):
        //
        //   let cachePath = storeDirectory.appendingPathComponent("cache").path
        //   let dataPath  = storeDirectory.path
        //
        //   let builder = ClientBuilder()
        //       .sessionPaths(dataPath: dataPath, cachePath: cachePath)
        //       .homeserverUrl(url: homeserverURL)
        //       .username(username: userID)
        //       .passphrase(passphrase: NSEKeychain.passphrase())  // 32 random bytes,
        //                                                          // persisted in
        //                                                          // keychain access group
        //       .setSessionDelegate(KeychainTokenRefresher())
        //
        //   let client = try await builder.build()
        //
        //   // First launch only: register the NSE as a separate device.
        //   //   try await client.matrixAuth().login(
        //   //       username: userID, password: ..., initialDeviceName: "Grid NSE"
        //   //   )
        //   // Subsequent launches: restore the persisted session token.
        //   try await client.restoreSession(session: Session(
        //       accessToken: accessToken,
        //       refreshToken: nil,
        //       userId: userID,
        //       deviceId: deviceID ?? "",
        //       homeserverUrl: homeserverURL,
        //       slidingSyncVersion: .native,
        //       oidcData: nil
        //   ))
        //
        //   let notifClient = try await client.notificationClient(
        //       processSetup: .singleProcess
        //   )
        //
        //   guard let item = try await notifClient.getNotification(
        //       roomId: roomID, eventId: eventID
        //   ) else {
        //       throw DecryptionError.eventNotFound
        //   }
        //
        //   let timelineEvent = item.event              // TimelineEvent
        //   let content = timelineEvent.eventType()     // .state(content: ...) | .messageLike(...)
        //   // For `m.room.member`, dig out membership / prev_membership
        //   // from the state content. Field names: verify against the SDK
        //   // version pinned in Package.resolved.
        //
        //   return DecryptedEvent(
        //       eventID: eventID,
        //       roomID: roomID,
        //       senderID: timelineEvent.senderId(),
        //       senderDisplayName: item.senderInfo.displayName,
        //       eventType: "m.room.member",
        //       stateKey: <state_key from event>,
        //       membership: <membership from content>,
        //       prevMembership: <prev_content.membership from unsigned>,
        //       isDirectInvite: item.isDirect,
        //       roomDisplayName: item.roomDisplayName
        //   )
        //
        // Field names (`senderInfo`, `roomDisplayName`, `isDirect`,
        // `senderId`, `eventType`) live on `NotificationItem` and
        // `TimelineEvent`. Names rotate between SDK releases — pin a version
        // and validate against the generated headers.
        //
        // Until that wiring lands, throw so the HTTP fallback path runs.
        // -----------------------------------------------------------------
        os_log(
            "fetchAndDecryptImpl: stub — SPM linked but call site not wired yet",
            log: decryptionLog, type: .info
        )
        throw DecryptionError.notificationFetchFailed("not implemented")
    }
    #endif
}
