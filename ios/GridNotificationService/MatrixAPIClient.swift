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

    /// Fetch a single event by ID from a room. The CS API
    /// `/rooms/{roomId}/event/{eventId}` endpoint returns the raw event,
    /// including `unsigned.prev_content` for state events (we rely on that
    /// to distinguish invite→join transitions).
    func fetchEvent(roomID: String, eventID: String) async throws -> MatrixEvent {
        let encodedRoomID = encode(roomID)
        let encodedEventID = encode(eventID)

        let urlString = "\(homeserverURL)/_matrix/client/v3/rooms/\(encodedRoomID)/event/\(encodedEventID)"
        return try await getJSON(urlString: urlString, decode: MatrixEvent.self)
    }

    /// Fetch an `m.room.member` state event for a specific user in a room.
    /// Used by the NSE to look up the sender's display name for invite/join
    /// notifications without pulling the whole `/members` list.
    func fetchRoomMember(roomID: String, userID: String) async throws -> MatrixEventContent {
        let encodedRoomID = encode(roomID)
        let encodedUserID = encode(userID)
        let urlString =
            "\(homeserverURL)/_matrix/client/v3/rooms/\(encodedRoomID)/state/m.room.member/\(encodedUserID)"
        return try await getJSON(urlString: urlString, decode: MatrixEventContent.self)
    }

    /// Fetch the room's name (`m.room.name`). Returns nil on 404 / no name set
    /// rather than throwing, because many rooms legitimately have no name and
    /// we want the notification to degrade to a generic body, not error.
    func fetchRoomName(roomID: String) async -> String? {
        let encodedRoomID = encode(roomID)
        let urlString =
            "\(homeserverURL)/_matrix/client/v3/rooms/\(encodedRoomID)/state/m.room.name/"
        struct NameState: Decodable { let name: String? }
        return try? await getJSON(urlString: urlString, decode: NameState.self).name
    }

    /// Fetch the current user's `m.direct` account data and return the set of
    /// room IDs that are flagged as direct (1:1) rooms.
    ///
    /// The endpoint returns `{ "<other_user_id>": ["!roomId:server", ...] }`,
    /// so we flatten all values.
    func fetchDirectRoomIDs(userID: String) async -> Set<String> {
        let encodedUserID = encode(userID)
        let urlString =
            "\(homeserverURL)/_matrix/client/v3/user/\(encodedUserID)/account_data/m.direct"
        guard let map = try? await getJSON(
            urlString: urlString,
            decode: [String: [String]].self
        ) else {
            return []
        }
        return Set(map.values.flatMap { $0 })
    }

    // MARK: - Internals

    private func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    private func getJSON<T: Decodable>(urlString: String, decode: T.Type) async throws -> T {
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
        return try JSONDecoder().decode(T.self, from: data)
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
    let stateKey: String?
    let content: MatrixEventContent?
    let unsigned: MatrixEventUnsigned?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case sender
        case roomId = "room_id"
        case stateKey = "state_key"
        case content
        case unsigned
    }
}

struct MatrixEventUnsigned: Decodable {
    /// For state events, the previous value of the state key (if any).
    /// We use this to tell an accepted-invite join (`prev_content.membership
    /// == "invite"`) from a fresh join.
    let prevContent: MatrixEventContent?

    enum CodingKeys: String, CodingKey {
        case prevContent = "prev_content"
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

    // For m.room.member
    let membership: String?
    let displayname: String?
    let isDirect: Bool?

    enum CodingKeys: String, CodingKey {
        case msgtype, body, algorithm, ciphertext, membership, displayname
        case senderKey = "sender_key"
        case sessionId = "session_id"
        case deviceId = "device_id"
        case isDirect = "is_direct"
    }
}

enum MatrixAPIError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
}
