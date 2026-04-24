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
                os_log("fetchEvent threw %{public}@ — trying member-state fallback",
                       log: nseLog, type: .error,
                       String(describing: error))

                // Synapse rejects /rooms/{id}/event/{eid} for invitees who
                // aren't members yet (typical 404). For invite pushes the
                // current-member state still works because invitees own a
                // m.room.member state event with membership=invite. Render
                // the invite banner from that.
                // Best-effort: try to read self-member state for richer
                // content. Synapse may 403 invitees here too, in which case
                // we fall through to a generic invite banner — under the
                // allowlisted policy a push the NSE can't decode is almost
                // always an invite (the only event type where the user
                // isn't yet a member of the room).
                if let me = currentUserID,
                   let member = try? await client.fetchRoomMember(
                       roomID: roomID, userID: me) {
                    os_log("member fallback fetched: membership=%{public}@ isDirect=%{public}d",
                           log: nseLog, type: .info,
                           member.membership ?? "<nil>",
                           (member.isDirect ?? false) ? 1 : 0)
                    if member.membership == "invite" {
                        let inviterDisplay = member.displayname ?? "Someone"
                        let isDirect = member.isDirect == true
                        let body: String
                        if isDirect {
                            body = "\(inviterDisplay) wants to share location with you"
                        } else if let name = await client.fetchRoomName(roomID: roomID),
                                  !name.isEmpty {
                            body = "\(inviterDisplay) invited you to \(name)"
                        } else {
                            body = "\(inviterDisplay) invited you"
                        }
                        bestAttemptContent.title = "Grid"
                        bestAttemptContent.body = body
                        bestAttemptContent.sound = .default
                        contentHandler(bestAttemptContent)
                        return
                    }
                    // Member-state readable but not invite — we shouldn't
                    // have been pushed for this; suppress.
                    os_log("member fallback: not invite, suppress", log: nseLog, type: .info)
                    self.suppressNotification(contentHandler: contentHandler)
                    return
                }

                // Member-state inaccessible (Synapse 403s invitees on it).
                // Room name is more permissive (stripped state) and is
                // typically readable. Treat as a generic invite — that's
                // overwhelmingly the cause under the allowlist policy.
                let roomName = await client.fetchRoomName(roomID: roomID)
                os_log("member fallback failed — generic invite banner, roomName=%{public}@",
                       log: nseLog, type: .info,
                       roomName ?? "<nil>")
                bestAttemptContent.title = "Grid"
                if let name = roomName, !name.isEmpty {
                    bestAttemptContent.body = "You're invited to \(name)"
                } else {
                    bestAttemptContent.body = "You have a new invite"
                }
                bestAttemptContent.sound = .default
                contentHandler(bestAttemptContent)
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
