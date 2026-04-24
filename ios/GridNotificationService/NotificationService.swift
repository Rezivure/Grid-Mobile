import UserNotifications

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
        self.contentHandler = contentHandler
        self.bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            suppressNotification(contentHandler: contentHandler)
            return
        }

        let userInfo = request.content.userInfo
        guard let eventID = userInfo["event_id"] as? String,
              let roomID = userInfo["room_id"] as? String else {
            // No event info — can't classify, so suppress.
            suppressNotification(contentHandler: contentHandler)
            return
        }

        let storage = SharedStorage()
        let currentUserID = storage.userID

        // Step 1: fast path — use the main app's pre-cached event hint if any.
        if let hint = storage.eventHint(for: eventID) {
            let action = EventClassifier.classify(hint: hint)
            if EventClassifier.apply(action: action, to: bestAttemptContent) {
                contentHandler(bestAttemptContent)
            } else {
                suppressNotification(contentHandler: contentHandler)
            }
            return
        }

        // Step 2: slow path — fetch the event from the homeserver and classify.
        guard storage.hasCredentials,
              let homeserver = storage.homeserverURL,
              let token = storage.accessToken else {
            // No credentials means the main app never bridged them into the
            // App Group. Under the allowlist policy we suppress rather than
            // show a generic "New activity" banner, which is just noise.
            suppressNotification(contentHandler: contentHandler)
            return
        }

        let client = MatrixAPIClient(homeserverURL: homeserver, accessToken: token)

        Task {
            do {
                let event = try await client.fetchEvent(roomID: roomID, eventID: eventID)
                let action = await EventClassifier.classifyWithContext(
                    event: event,
                    roomID: roomID,
                    currentUserID: currentUserID,
                    client: client
                )
                if EventClassifier.apply(action: action, to: bestAttemptContent) {
                    contentHandler(bestAttemptContent)
                } else {
                    self.suppressNotification(contentHandler: contentHandler)
                }
            } catch {
                // Network / decode error — suppress. Showing a fallback here
                // would both leak the fact that *some* activity happened and
                // violate the allowlist policy.
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
