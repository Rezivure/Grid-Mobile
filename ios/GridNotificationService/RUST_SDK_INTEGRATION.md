# MatrixRustSDK integration (Phase 3 skeleton)

This NSE is wired for E2EE-aware push notifications via
`matrix-rust-sdk`'s Swift bindings. The Swift code is in place but the
Swift Package dependency is **not yet added** — adding SPM deps to a
`pbxproj` by hand without an Xcode build to verify is risky, so this
last step is done via Xcode UI.

`canImport(MatrixRustSDK)` guards keep `NotificationDecryptionClient.swift`
compiling as a no-op until the package is linked. In the no-op state the
NSE behaves exactly as before (HTTP-only, member-state fallback).

## Adding the dependency (one-time, by hand)

1. Open `ios/Runner.xcworkspace` in Xcode.
2. File → Add Package Dependencies…
3. URL:
   `https://github.com/element-hq/matrix-rust-components-swift`
4. Dependency rule: **Up to Next Major Version** from `26.04.01` (or
   pin to an exact tag for stability — Element-X pins exact versions).
5. **Crucially**: in the "Add to Target" dialog, select
   **GridNotificationService** ONLY. Do not add to `Runner` — Runner
   uses matrix-dart-sdk via Flutter and adding the rust-sdk to it
   would bloat the binary by ~30 MB and risk symbol conflicts.
6. Verify `IPHONEOS_DEPLOYMENT_TARGET` for the NSE target ≥ 16.0
   (currently 26.2 — fine).

## Verifying the link

After SPM resolves:

- `import MatrixRustSDK` should resolve in
  `NotificationDecryptionClient.swift`.
- The `#if canImport(MatrixRustSDK)` block becomes live; the stub still
  throws `.notificationFetchFailed("not implemented")` so HTTP fallback
  continues until the actual API calls are filled in.

## Remaining work (TODO comments in `NotificationDecryptionClient.swift`)

1. **Bootstrap a rust-sdk Client in `fetchAndDecryptImpl`**:
   - First launch: register a new device via `client.matrixAuth().login(...)`
     — needs the user's password OR a `m.login.token` minted by main app
     and passed via the AppGroupBridge. Recommend: main app calls
     `/login/get_token` (MSC3882) and writes the resulting token into
     the app group; NSE consumes it on cold start.
   - Subsequent launches: `client.restoreSession(...)` from the
     persisted access token in keychain access group
     `app.mygrid.grid.shared`.
2. **Persist the rust-sdk session** in keychain (not app-group
   UserDefaults — access tokens belong in keychain). Use a
   `ClientSessionDelegate` for refresh.
3. **Verify the NSE device** so the main app's `ShareKeysWith.all`
   actually shares megolm keys to it. Two paths:
   - Cross-signing: bridge the user's master signing key from main app
     to NSE on first launch (requires user re-auth or stored backup
     key).
   - Self-verification via emoji on the user's main device — same
     flow as adding any new client.
4. **Map `NotificationItem` → `DecryptedEvent`** (field names listed
   in the file's TODO).

## Known risks

- **First-push latency**: cold-start of rust-sdk Client +
  sliding-sync handshake can take several seconds. Element-X measures
  ~2–5s on a warm device. NSE budget is ~30s. Acceptable but watch
  it.
- **Key sharing not firing**: if the main app's
  `shareKeysWith: ShareKeysWith.all` is sending keys but the NSE
  device isn't trusted (no cross-signing), the keys won't flow. The
  HTTP fallback handles this case for invites (the only event type
  we currently push), so degradation is graceful.
- **Store corruption**: if the main app ever crashes mid-write or
  the NSE is killed mid-write, the SQLite store may be left in a bad
  state. rust-sdk uses WAL so this is rare, but the code should
  handle a `clientBuildFailed` by deleting the store and re-bootstrapping.
- **Binary size**: MatrixRustSDK adds ~30 MB to the NSE bundle. NSE
  hard limit is 24 MB on older iOS. Verify on a real device build —
  if it hits the cap, the SDK ships features we don't need and can be
  trimmed via custom-built xcframework.

## File map

- `NotificationDecryptionClient.swift` — rust-sdk wrapper (skeleton).
- `EventClassifier.swift` — adds `classifyDecrypted(...)` for the
  rust-sdk model. Original HTTP-path classifiers untouched.
- `NotificationService.swift` — tries `NotificationDecryptionClient`
  first; falls through to existing HTTP path on any error
  (including `.sdkNotLinked`).
- `MatrixAPIClient.swift` / `SharedStorage.swift` — unchanged.
