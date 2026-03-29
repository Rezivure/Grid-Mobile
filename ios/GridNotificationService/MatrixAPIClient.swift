import Foundation

/// Lightweight Matrix CS API client for fetching events in the NSE.
/// No heavy SDK — just URLSession calls to stay under 24MB.
final class MatrixAPIClient {
    private let homeserverURL: String
    private let accessToken: String
    private let session: URLSession
    
    init(homeserverURL: String, accessToken: String) {
        self.homeserverURL = homeserverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.accessToken = accessToken
        
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: config)
    }
    
    /// Fetch a single event by ID from a room
    func fetchEvent(roomID: String, eventID: String) async throws -> MatrixEvent {
        let encodedRoomID = roomID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomID
        let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID
        
        let urlString = "\(homeserverURL)/_matrix/client/v3/rooms/\(encodedRoomID)/event/\(encodedEventID)"
        guard let url = URL(string: urlString) else {
            throw MatrixAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MatrixAPIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw MatrixAPIError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(MatrixEvent.self, from: data)
    }
    
    deinit {
        session.invalidateAndCancel()
    }
}

// MARK: - Models

struct MatrixEvent: Decodable {
    let type: String
    let eventId: String?
    let sender: String?
    let roomId: String?
    let content: MatrixEventContent?
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case sender
        case roomId = "room_id"
        case content
    }
}

struct MatrixEventContent: Decodable {
    // For m.room.message
    let msgtype: String?
    let body: String?
    
    // For m.room.encrypted
    let algorithm: String?
    let ciphertext: String?
    let senderKey: String?
    let sessionId: String?
    let deviceId: String?
    
    enum CodingKeys: String, CodingKey {
        case msgtype, body, algorithm, ciphertext
        case senderKey = "sender_key"
        case sessionId = "session_id"
        case deviceId = "device_id"
    }
}

enum MatrixAPIError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
}
