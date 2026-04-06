import UserNotifications

/// Grid Notification Service Extension
///
/// Intercepts push notifications to:
/// 1. Classify the Matrix event type
/// 2. Suppress silent events (location, avatar, map icons)
/// 3. Format meaningful notifications for user-facing events
/// 4. Fall back to "New activity in Grid" if decryption/classification fails
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
            contentHandler(request.content)
            return
        }
        
        let userInfo = request.content.userInfo
        guard let eventID = userInfo["event_id"] as? String,
              let roomID = userInfo["room_id"] as? String else {
            // No event info — show as-is
            contentHandler(bestAttemptContent)
            return
        }
        
        let storage = SharedStorage()
        
        // Step 1: Check if main app pre-cached a hint for this event
        if let hint = storage.eventHint(for: eventID) {
            let action = EventClassifier.classify(hint: hint)
            if EventClassifier.apply(action: action, to: bestAttemptContent) {
                contentHandler(bestAttemptContent)
            } else {
                // Suppress: deliver empty notification that iOS will discard
                suppressNotification(contentHandler: contentHandler)
            }
            return
        }
        
        // Step 2: Try to fetch the event from homeserver
        guard storage.hasCredentials,
              let homeserver = storage.homeserverURL,
              let token = storage.accessToken else {
            // No credentials — show fallback
            bestAttemptContent.title = "Grid"
            bestAttemptContent.body = "New activity in Grid"
            contentHandler(bestAttemptContent)
            return
        }
        
        let client = MatrixAPIClient(homeserverURL: homeserver, accessToken: token)
        
        Task {
            do {
                let event = try await client.fetchEvent(roomID: roomID, eventID: eventID)
                let action = EventClassifier.classify(event: event)
                
                if EventClassifier.apply(action: action, to: bestAttemptContent) {
                    contentHandler(bestAttemptContent)
                } else {
                    self.suppressNotification(contentHandler: contentHandler)
                }
            } catch {
                // Network error — show fallback
                bestAttemptContent.title = "Grid"
                bestAttemptContent.body = "New activity in Grid"
                contentHandler(bestAttemptContent)
            }
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the 30s limit. Deliver whatever we have.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            bestAttemptContent.title = "Grid"
            bestAttemptContent.body = "New activity in Grid"
            contentHandler(bestAttemptContent)
        }
    }
    
    /// Suppress a notification by delivering an empty content with no alert.
    /// iOS will not display a notification without a title/body.
    private func suppressNotification(contentHandler: @escaping (UNNotificationContent) -> Void) {
        let empty = UNMutableNotificationContent()
        // Setting empty title+body effectively suppresses the visible notification.
        // The badge/sound are also cleared.
        contentHandler(empty)
    }
}
