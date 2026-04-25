# Push Notifications Test Plan — Element-way rewrite

End-to-end test plan for the E2EE push architecture introduced in this PR. Covers iOS, Android (GMS), and Android (GrapheneOS / UnifiedPush).

## Architecture recap

- **No synthetic-message workaround.** Real Matrix `m.room.member` events drive the pushes; no fake `grid.member.join` markers are posted by the app.
- **Server-side push rules** (applied on every login):
  - Override `grid.member.join`: `notify` on `m.room.member` events with `membership == "join"`.
  - Disable underride defaults: `.m.rule.message`, `.m.rule.room_one_to_one`, `.m.rule.encrypted`, `.m.rule.encrypted_room_one_to_one` — no chat-message pushes.
  - Kept: `.m.rule.invite_for_me` (default, enabled) — invites push.
- **Decryption in the extension/background process**:
  - iOS NSE → `MatrixRustSDK.NotificationClient` (skeleton landed; full wiring requires the Xcode SPM add — see §iOS).
  - Android FCM handler → headless matrix-dart-sdk `Client` over the app's SQLite DB.
  - Android UnifiedPush handler → same headless client, different transport.

## Expected banners (all 3 platforms)

| Event | Banner |
|---|---|
| Direct-room invite received (`Grid:Direct:...`) | "*sender display name* wants to share location with you" |
| Group invite received (`Grid:Group:...`) | "*sender display name* invited you to *group name*" |
| Someone joins a group you're in | "*sender display name* joined *group name*" |
| Someone accepts your direct-room invite (friendship accept) | "*sender display name* accepted your request" |
| Anything else (chat, silent events, etc.) | **No push** (filtered server-side by push rules) |

## iOS

### Status: **skeleton only**

The NSE now calls `NotificationDecryptionClient` first, falls back to plain-HTTP `MatrixAPIClient` on any failure. The rust-sdk wrapper is gated by `#if canImport(MatrixRustSDK)` and no-ops until the SPM dependency is added in Xcode.

### Human steps before test

1. Open `ios/Runner.xcworkspace` in Xcode.
2. **File → Add Package Dependencies**:
   - URL: `https://github.com/element-hq/matrix-rust-components-swift`
   - Version: `26.04.01` or later
   - Add to target: **`GridNotificationService` only** (not Runner)
3. Confirm `ios/GridNotificationService/NotificationDecryptionClient.swift` resolves `import MatrixRustSDK` after the build.
4. Implement the TODO block in `fetchAndDecryptImpl` against the installed SDK version (the skeleton has the decrypted-event mapping ready).
5. At developer.apple.com, confirm the App ID `app.mygrid.grid.GridNotificationService` has keychain access group `app.mygrid.grid.shared` enabled.

### What works today on iOS (without the rust-sdk add)

- Invite banners (`m.room.member` state events are unencrypted; HTTP path renders them fine).
- Suppression of non-allowlisted events (via push rules).

### What won't work until the rust-sdk wiring is done

- Group-join and friendship-accept banners where the event is encrypted (plain HTTP can't decrypt → falls back to member-state lookup → renders only if room state is readable).

### Scenarios to test on iOS

1. **Install** the next TestFlight build. Open Grid, sign in, confirm Console.app shows `[Push] Override rule grid.member.join set` and the four underride-disabled lines.
2. **Invite from a second account**: have another Matrix user invite lily to a DM or a group. Banner should render with the specific text. ✅ expected to work today.
3. **Regular chat message from a joined room**: another user sends text. Banner: **none**. Sygnal logs should show no APNs call.
4. (After rust-sdk wiring) **Group join**: have another user join a group you're already in. Banner: "X joined Y".
5. (After rust-sdk wiring) **Friendship accept**: another user accepts your DM invite. Banner: "X accepted your request".

## Android (Google Play Services)

### Status: **end-to-end working in the code**, needs device confirmation.

FCM background handler now instantiates a real matrix-dart-sdk `Client` against the same SQLite DB path (`grid_app_matrix.db` under `getApplicationSupportDirectory()`) as the foreground client, calls `vod.init()` in the isolate, decrypts via `client.encryption.decryptRoomEvent(...)`, and hands decrypted content to the same `NotificationDisplay` classifier as UnifiedPush.

### Human steps before test

- Bump build in Play Console / sideload the APK.
- First run after install may be slower (SQLite open + olm) — expected.

### Scenarios to test on Android (GMS)

1. Receive an invite → banner renders.
2. Regular chat message → no banner.
3. Receive an m.room.member join of a joined group → banner "X joined Y" (requires megolm keys already in DB — usually true after any prior foreground session).
4. Receive friendship accept → banner "X accepted your request".
5. Kill the app, receive an invite → banner still renders (headless client init covers cold start).

### Known limitations

- If a push arrives before any foreground sync has ever populated the Room, `getRoomById` returns null → silent suppression. Cold first-run only.
- If megolm keys for the encrypted event are not yet in the DB (forwarded after app was killed), decryption returns encrypted → silent suppression. User needs to open the app to catch up.

## Android (GrapheneOS / UnifiedPush)

### Status: **code wired**, needs an end-to-end test with the Grid push gateway.

New file: `lib/services/push/unifiedpush_background_handler.dart`. Receives `PushMessage` from ntfy via the UnifiedPush broadcast, JSON-parses the payload, and calls the same `NotificationDisplay.processAndShow` pipeline as FCM. Decryption logic is identical — only the transport differs.

### Human steps before test

1. Install a UnifiedPush distributor on the Graphene device (**ntfy-android** recommended since the gateway is ntfy).
2. Point ntfy-android at `https://push.mygrid.app` or leave it default (check the Grid pusher's `data.url` — the gateway URL should be `https://push.mygrid.app/_matrix/push/v1/notify`).
3. Install Grid APK (no GMS variant; the code path auto-detects and registers UP).
4. Open Grid — `[Push] Registering UnifiedPush distributor...` log line should appear, followed by `Pusher registered: PushTransport.unifiedPush / app.mygrid.grid.android.unifiedpush`.

### Known caveats

- The push gateway at `push.mygrid.app` must speak **RFC 8291 Web Push encryption** (the `aesgcm` / `aes128gcm` content-encodings) with the `pubKeySet` the app registers via UnifiedPush. If it currently just proxies Matrix push JSON in plaintext, we'll get `message.decrypted == false` and silently suppress. Verify gateway behavior before testing.
- `pubKeySet` is owned by the client — currently we do NOT send it in the Matrix pusher `data.pubKeySet`. If the gateway needs it, we have to extend the `PusherData.additionalProperties` to include the keys. Follow-up if this shows up.
- Distributor installation is a one-time user action. Without a UP distributor, the app falls through to an error on pusher registration.

### Scenarios to test on Graphene

Same five scenarios as FCM. Expect functional parity once the gateway encryption path is verified.

## Rollback

If the new rules leave a user's account in a broken state, they can be reset manually:

```
curl -X PUT 'https://matrix.mygrid.app/_matrix/client/v3/pushrules/global/underride/.m.rule.message/enabled' \
  -H 'Authorization: Bearer <token>' -d '{"enabled":true}'
```

(Repeat for the other three underrides, delete the `grid.member.join` override.) Or log out and back in once the client code reverts.

## Outstanding follow-ups (not in this PR)

- iOS: finish the `NotificationDecryptionClient` TODO block against the real rust-sdk API.
- iOS: bootstrap cross-signing for the NSE device so main app shares megolm keys to it.
- Android: consider requesting missing keys in background mode for the "push arrived, keys missing" case.
- UnifiedPush: verify / extend the push gateway to handle RFC 8291 encryption with the client-registered `pubKeySet`.
- When chat ships: flip the four underrides back on and wire proper chat push rendering in both NSE and Android handler.
