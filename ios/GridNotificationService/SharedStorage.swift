import Foundation

/// Shared storage between main app and NSE via App Group container
final class SharedStorage {
    static let appGroupID = "group.app.mygrid.grid"
    static let keychainGroup = "app.mygrid.grid.shared"
    
    private let defaults: UserDefaults?
    
    init() {
        self.defaults = UserDefaults(suiteName: SharedStorage.appGroupID)
    }
    
    // MARK: - Matrix Credentials
    
    var homeserverURL: String? {
        defaults?.string(forKey: "homeserver_url")
    }
    
    var accessToken: String? {
        defaults?.string(forKey: "access_token")
    }
    
    var userID: String? {
        defaults?.string(forKey: "user_id")
    }
    
    var deviceID: String? {
        defaults?.string(forKey: "device_id")
    }
    
    var hasCredentials: Bool {
        homeserverURL != nil && accessToken != nil
    }
    
    // MARK: - Event Hints Cache
    // The main app can pre-write decrypted event hints so the NSE
    // doesn't need to decrypt. Format: {event_id: {type: String, summary: String}}
    
    private var hintsFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStorage.appGroupID)?
            .appendingPathComponent("nse_event_hints.json")
    }
    
    func eventHint(for eventID: String) -> EventHint? {
        guard let url = hintsFileURL,
              let data = try? Data(contentsOf: url),
              let hints = try? JSONDecoder().decode([String: EventHint].self, from: data) else {
            return nil
        }
        return hints[eventID]
    }
    
    /// Write hints from main app side (called via method channel)
    func writeEventHint(eventID: String, hint: EventHint) {
        guard let url = hintsFileURL else { return }
        
        var hints: [String: EventHint] = [:]
        if let data = try? Data(contentsOf: url) {
            hints = (try? JSONDecoder().decode([String: EventHint].self, from: data)) ?? [:]
        }
        
        hints[eventID] = hint
        
        // Keep only last 100 hints to bound storage
        if hints.count > 100 {
            // Remove oldest (no ordering, just trim)
            let excess = hints.count - 100
            for key in hints.keys.prefix(excess) {
                hints.removeValue(forKey: key)
            }
        }
        
        if let data = try? JSONEncoder().encode(hints) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

struct EventHint: Codable {
    let type: String      // e.g. "m.location", "m.avatar.announcement", "m.text", "sos", "geofence"
    let summary: String?  // e.g. "John arrived at Home", "SOS from Jane"
    let senderName: String?
}
