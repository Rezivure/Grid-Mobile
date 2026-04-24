import UserNotifications
import os.log

// Subsystem picks up in Console.app when filtering by `app.mygrid.grid`.
private let nseLog = OSLog(subsystem: "app.mygrid.grid", category: "NSE")

/// Grid Notification Service Extension
///
/// Intercepts push notifications and, under the product's allowlist policy,
/// only renders a user-visible banner for:
///   1. Room invites (group or direct)
///   2. Someone joining a group room the user is already in
///   3. Someone accepting a direct-room invite the user sent (friendship accept)
///
/// Everything else — messages, location updates, avatar/map-icon events,
/// typing, receipts, own-actions, unknown types, and all failure modes — is
/// suppressed. "Suppressed" means: deliver empty content so iOS drops the
/// notification without rendering anything.
///
/// The APNs pusher is registered with `format: event_id_only` and a
/// `default_payload` of `aps.alert.body = " "`, so even in the worst case
/// (NSE times out or OS never schedules us) the user sees no leaked content.
class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        os_log("didReceive fired, userInfo keys=%{public}@",
               log: nseLog, type: .info,
               "\(Array(request.content.userInfo.keys).map(String.init(describing:)))")

        self.contentHandler = contentHandler
        self.bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            os_log("suppress: could not mutableCopy content", log: nseLog, type: .error)
            suppressNotification(contentHandler: contentHandler)
            return
        }

        let userInfo = request.content.userInfo
        guard let eventID = userInfo["event_id"] as? String,
              let roomID = userInfo["room_id"] as? String else {
            // No event info — can't classify, so suppress.
            os_log("suppress: no event_id/room_id in userInfo", log: nseLog, type: .error)
            suppressNotification(contentHandler: contentHandler)
            return
        }
        os_log("parsed eventID=%{public}@ roomID=%{public}@", log: nseLog, type: .info, eventID, roomID)

        let storage = SharedStorage()
        let currentUserID = storage.userID
        os_log("storage: hasCredentials=%{public}d userID=%{public}@",
               log: nseLog, type: .info,
               storage.hasCredentials ? 1 : 0,
               currentUserID ?? "<nil>")

        // Step 1: fast path — use the main app's pre-cached event hint if any.
        if let hint = storage.eventHint(for: eventID) {
            os_log("fast-path hint hit: type=%{public}@", log: nseLog, type: .info, hint.type)
            let action = EventClassifier.classify(hint: hint)
            if EventClassifier.apply(action: action, to: bestAttemptContent) {
                os_log("hint -> show", log: nseLog, type: .info)
                contentHandler(bestAttemptContent)
            } else {
                os_log("hint -> suppress", log: nseLog, type: .info)
                suppressNotification(contentHandler: contentHandler)
            }
            return
        }

        // Step 2: slow path — fetch the event from the homeserver and classify.
        guard storage.hasCredentials,
              let homeserver = storage.homeserverURL,
              let token = storage.accessToken else {
            os_log("suppress: no credentials in app group", log: nseLog, type: .error)
            suppressNotification(contentHandler: contentHandler)
            return
        }

        let client = MatrixAPIClient(homeserverURL: homeserver, accessToken: token)

        Task {
            do {
                os_log("fetching event...", log: nseLog, type: .info)
                let event = try await client.fetchEvent(roomID: roomID, eventID: eventID)
                os_log("fetched event type=%{public}@ membership=%{public}@ stateKey=%{public}@ isDirect=%{public}d",
                       log: nseLog, type: .info,
                       event.type,
                       event.content?.membership ?? "<nil>",
                       event.stateKey ?? "<nil>",
                       (event.content?.isDirect ?? false) ? 1 : 0)
                let action = await EventClassifier.classifyWithContext(
                    event: event,
                    roomID: roomID,
                    currentUserID: currentUserID,
                    client: client
                )
                if EventClassifier.apply(action: action, to: bestAttemptContent) {
                    os_log("classifier -> show title=%{public}@ body=%{public}@",
                           log: nseLog, type: .info,
                           bestAttemptContent.title, bestAttemptContent.body)
                    contentHandler(bestAttemptContent)
                } else {
                    os_log("classifier -> suppress", log: nseLog, type: .info)
                    self.suppressNotification(contentHandler: contentHandler)
                }
            } catch {
                os_log("suppress: fetchEvent threw %{public}@",
                       log: nseLog, type: .error,
                       String(describing: error))
                self.suppressNotification(contentHandler: contentHandler)
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // We're about to be killed by iOS. We haven't finished classifying,
        // so we don't know if this event is allowlisted. Suppress — iOS will
        // fall back to the APNs default_payload, which itself is a silent
        // placeholder (body = " ").
        if let contentHandler = contentHandler {
            suppressNotification(contentHandler: contentHandler)
        }
    }

    /// Suppress a notification by delivering empty content.
    ///
    /// iOS suppresses a notification entirely when the delivered content has
    /// no title and no body. We also zero out sound, badge, and interruption
    /// level to be defensive about vendor-specific rendering.
    private func suppressNotification(contentHandler: @escaping (UNNotificationContent) -> Void) {
        let empty = UNMutableNotificationContent()
        empty.title = ""
        empty.body = ""
        empty.sound = nil
        empty.badge = nil
        if #available(iOS 15.0, *) {
            empty.interruptionLevel = .passive
            empty.relevanceScore = 0
        }
        contentHandler(empty)
    }
}
