import UserNotifications

/// Classifies Matrix events and decides how to format (or suppress) notifications.
enum NotificationAction {
    case suppress                           // Don't show notification (location, avatar, map icon events)
    case showDefault                        // Show fallback "New activity in Grid"
    case showMessage(title: String, body: String)  // Show formatted notification
    case showCritical(title: String, body: String)  // Critical alert (SOS)
}

final class EventClassifier {
    
    /// Classify based on a pre-cached event hint from the main app
    static func classify(hint: EventHint) -> NotificationAction {
        let type = hint.type.lowercased()
        
        // Suppress silent/background event types
        if type == "m.location" { return .suppress }
        if type.hasPrefix("m.avatar") { return .suppress }
        if type.hasPrefix("m.map.icon") { return .suppress }
        
        // SOS / Emergency
        if type == "sos" || type == "m.sos.alert" {
            let title = "🆘 Emergency Alert"
            let body = hint.summary ?? "SOS alert from a Grid member"
            return .showCritical(title: title, body: body)
        }
        
        // Geofence
        if type == "geofence" || type.hasPrefix("m.geofence") {
            let body = hint.summary ?? "Geofence event"
            return .showMessage(title: "Grid", body: body)
        }
        
        // Text message (future chat feature)
        if type == "m.text" || type == "m.room.message" {
            let sender = hint.senderName ?? "Someone"
            let body = hint.summary ?? "sent a message"
            return .showMessage(title: sender, body: body)
        }
        
        return .showDefault
    }
    
    /// Classify based on a fetched (unencrypted) Matrix event
    static func classify(event: MatrixEvent) -> NotificationAction {
        // If the event is encrypted and we can't decrypt, show fallback
        if event.type == "m.room.encrypted" {
            return .showDefault
        }
        
        // For unencrypted m.room.message, check msgtype
        if event.type == "m.room.message", let msgtype = event.content?.msgtype {
            switch msgtype {
            case "m.location":
                return .suppress
            case _ where msgtype.hasPrefix("m.avatar"):
                return .suppress
            case _ where msgtype.hasPrefix("m.map.icon"):
                return .suppress
            case "m.text":
                let body = event.content?.body ?? "New message"
                return .showMessage(title: "Grid", body: body)
            default:
                return .showDefault
            }
        }
        
        // Room member events, etc.
        if event.type == "m.room.member" {
            return .suppress  // Don't notify on join/leave
        }
        
        return .showDefault
    }
    
    /// Apply the classification to a notification content object
    static func apply(action: NotificationAction, to content: UNMutableNotificationContent) -> Bool {
        switch action {
        case .suppress:
            // Return false to indicate notification should be suppressed
            return false
            
        case .showDefault:
            content.title = "Grid"
            content.body = "New activity in Grid"
            content.sound = .default
            return true
            
        case .showMessage(let title, let body):
            content.title = title
            content.body = body
            content.sound = .default
            return true
            
        case .showCritical(let title, let body):
            content.title = title
            content.body = body
            content.sound = UNNotificationSound.defaultCritical
            content.interruptionLevel = .critical
            return true
        }
    }
}
