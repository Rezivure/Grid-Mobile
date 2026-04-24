import UserNotifications

/// Classifies Matrix events and decides how to format (or suppress) notifications.
///
/// Policy (product decision, 2026-04):
///   The ONLY user-visible pushes are:
///     1. Room invites (group or direct)
///     2. Someone joining a GROUP room the user is already in
///     3. Someone accepting a DIRECT-room invite the user sent (friendship accept)
///
///   Everything else — messages, location updates, avatar/map-icon announcements,
///   typing, receipts, own actions — is suppressed (no banner, no sound, no badge).
enum NotificationAction {
    case suppress                                   // Do not show notification
    case showMessage(title: String, body: String)   // Standard banner
}

final class EventClassifier {

    /// Classify based on a pre-cached event hint from the main app.
    ///
    /// The hint path is deliberately conservative: the main app currently
    /// writes hints for silent events (location / avatar / map icon) and
    /// nothing else. Anything not explicitly allowlisted is suppressed.
    static func classify(hint: EventHint) -> NotificationAction {
        let type = hint.type.lowercased()

        // Hints for invite / join state are not written today; if we ever
        // start writing them, pass them straight through.
        if type == "m.room.member.invite" {
            let sender = hint.senderName ?? "Someone"
            return .showMessage(title: "Grid", body: "\(sender) invited you")
        }
        if type == "m.room.member.join.group" {
            let sender = hint.senderName ?? "Someone"
            let summary = hint.summary ?? "joined a group"
            return .showMessage(title: "Grid", body: "\(sender) \(summary)")
        }
        if type == "m.room.member.join.direct" {
            let sender = hint.senderName ?? "Someone"
            return .showMessage(title: "Grid", body: "\(sender) accepted your invite")
        }

        // Every other hint — location, avatar, map icon, message, sos,
        // geofence, unknown — is suppressed under the new policy.
        return .suppress
    }

    /// Classify a fetched event **without any additional context**. This is
    /// used as a fast path / fallback; it only allows the unambiguously
    /// decidable cases (invite with matching state_key). For join-vs-direct
    /// disambiguation see `classifyWithContext`.
    static func classify(event: MatrixEvent, currentUserID: String?) -> NotificationAction {
        // Synthetic Grid system message ("X joined room") posted by the
        // joining user's app. Allowlisted because Matrix's default push
        // rules don't notify on m.room.member joins and we can't easily
        // override them server-side.
        if event.type == "m.room.message",
           event.content?.msgtype == "grid.member.join" {
            let body = event.content?.body ?? "Someone joined a group"
            return .showMessage(title: "Grid", body: body)
        }

        guard event.type == "m.room.member" else {
            // Messages, encrypted events, location updates, etc. — all suppressed.
            return .suppress
        }
        guard let membership = event.content?.membership else {
            return .suppress
        }

        let senderDisplay = event.content?.displayname ?? event.sender ?? "Someone"

        switch membership {
        case "invite":
            // Only notify on invites *to this user*, not invites to others.
            if let me = currentUserID, event.stateKey == me {
                return .showMessage(title: "Grid", body: "\(senderDisplay) invited you")
            }
            return .suppress
        case "join":
            // Without room context we can't tell direct from group, or
            // distinguish friendship-accept from fresh join. The async
            // `classifyWithContext` path handles that; without context we
            // suppress to avoid noisy own-joins / mid-session joins.
            return .suppress
        default:
            // leave, ban, knock — never user-visible.
            return .suppress
        }
    }

    /// Fully contextual classification. Fetches room state via [client] to
    /// decide direct-vs-group and invite-accept-vs-fresh-join.
    ///
    /// Callers should always prefer this over [classify(event:currentUserID:)]
    /// when they have a live `MatrixAPIClient`.
    static func classifyWithContext(
        event: MatrixEvent,
        roomID: String,
        currentUserID: String?,
        client: MatrixAPIClient
    ) async -> NotificationAction {
        // Synthetic Grid join message — render the body directly.
        if event.type == "m.room.message",
           event.content?.msgtype == "grid.member.join" {
            let body = event.content?.body ?? "Someone joined a group"
            return .showMessage(title: "Grid", body: body)
        }

        // `roomID` is passed explicitly because the CS API
        // `/rooms/{roomId}/event/{eventId}` response often omits `room_id`
        // from the body (it's already in the URL), so `event.roomId` is
        // frequently nil even for valid events.
        guard event.type == "m.room.member",
              let membership = event.content?.membership
        else {
            return .suppress
        }

        // Resolve the actor's display name. Prefer the event's content
        // displayname (for join events it's the joiner; for invite events
        // it's the invitee). For invites we actually want the *sender*'s
        // name, so look them up if missing.
        let actorUserID: String? = (membership == "invite") ? event.sender : event.stateKey
        let actorDisplay = await resolveDisplayName(
            event: event,
            userID: actorUserID,
            roomID: roomID,
            client: client
        )

        switch membership {
        case "invite":
            // Only our own invites are user-visible.
            guard let me = currentUserID, event.stateKey == me else {
                return .suppress
            }
            // Differentiate group vs direct when the inviter flagged
            // `is_direct: true` (Matrix convention for DM invites).
            if event.content?.isDirect == true {
                return .showMessage(
                    title: "Grid",
                    body: "\(actorDisplay) wants to share location with you"
                )
            }
            if let roomName = await client.fetchRoomName(roomID: roomID), !roomName.isEmpty {
                return .showMessage(
                    title: "Grid",
                    body: "\(actorDisplay) invited you to \(roomName)"
                )
            }
            return .showMessage(title: "Grid", body: "\(actorDisplay) invited you")

        case "join":
            // Never notify on the current user's own joins.
            if let me = currentUserID, event.stateKey == me {
                return .suppress
            }

            // Direct-room join = friendship accept (only when the *previous*
            // membership was an invite we sent; a fresh join into a direct
            // room we didn't initiate isn't actionable and stays silent).
            let directRooms: Set<String>
            if let me = currentUserID {
                directRooms = await client.fetchDirectRoomIDs(userID: me)
            } else {
                directRooms = []
            }
            let isDirect = directRooms.contains(roomID)
            let prevMembership = event.unsigned?.prevContent?.membership

            if isDirect {
                if prevMembership == "invite" {
                    return .showMessage(
                        title: "Grid",
                        body: "\(actorDisplay) accepted your invite"
                    )
                }
                // Someone joining a DM room via some other path (re-join, etc.) —
                // not an actionable event under the spec'd policy.
                return .suppress
            }

            // Group room join: always notify, with the group name when known.
            if let roomName = await client.fetchRoomName(roomID: roomID), !roomName.isEmpty {
                return .showMessage(
                    title: "Grid",
                    body: "\(actorDisplay) joined \(roomName)"
                )
            }
            return .showMessage(title: "Grid", body: "\(actorDisplay) joined a group")

        default:
            return .suppress
        }
    }

    /// Apply the classification to a notification content object.
    /// Returns `true` if the notification should be shown; `false` if the
    /// caller should fall through to `suppressNotification(...)`.
    static func apply(action: NotificationAction, to content: UNMutableNotificationContent) -> Bool {
        switch action {
        case .suppress:
            return false
        case .showMessage(let title, let body):
            content.title = title
            content.body = body
            content.sound = .default
            return true
        }
    }

    // MARK: - Helpers

    private static func resolveDisplayName(
        event: MatrixEvent,
        userID: String?,
        roomID: String,
        client: MatrixAPIClient
    ) async -> String {
        // For a member event where the actor is also the state_key, the
        // event's own content.displayname is the canonical value.
        if event.stateKey == userID, let name = event.content?.displayname, !name.isEmpty {
            return name
        }
        if let userID = userID {
            if let member = try? await client.fetchRoomMember(roomID: roomID, userID: userID),
               let name = member.displayname, !name.isEmpty {
                return name
            }
            // Fall back to the Matrix ID localpart, which is still nicer
            // than the bare MXID for end users.
            return localpart(of: userID)
        }
        return "Someone"
    }

    private static func localpart(of userID: String) -> String {
        // "@alice:example.com" → "alice"
        guard userID.hasPrefix("@"), let colon = userID.firstIndex(of: ":") else { return userID }
        return String(userID[userID.index(after: userID.startIndex)..<colon])
    }
}
