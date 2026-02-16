# Grid-Mobile Release Pipeline Configuration

This document describes the automated release pipeline setup and requirements for enabling automated App Store and Play Store uploads.

## Overview

The Grid-Mobile release pipeline consists of three tiers:

1. **Core Tier** (`ci.yml`) - Fast validation on every push/PR (~5 min)
2. **Extended Tier** - Pre-merge validation with broader test coverage (~15 min) 
3. **Release Tier** (`release.yml`) - Complete pre-release validation (~30-60 min)

## Release Workflow

### Trigger Schedule
- **Automatic**: Every Sunday at 2:00 AM EST via cron
- **Manual**: Via GitHub Actions "workflow_dispatch" trigger

### Release Process

1. **Change Detection**
   - Compares `HEAD` with the latest release tag
   - Skips release if no commits since last release
   - Auto-generates changelog from commit messages

2. **Version Management**
   - Auto-increments build number in `pubspec.yaml`
   - Commits version bump to repository
   - Format: `major.minor.patch+buildnum`

3. **Build Generation**
   - iOS: `flutter build ipa --release`
   - Android: `flutter build appbundle --release`
   - Validates both builds complete successfully

4. **Test Validation**
   - All unit tests (`flutter test`)
   - Complete Maestro test suite (81 flows)
   - Pre-release stress testing gauntlet (flows 65-81)

5. **Release Creation**
   - Creates Git tag (`v1.2.3+456`)
   - Creates GitHub Release with changelog
   - Uploads IPA and AAB as release artifacts

6. **Store Upload** (TODO - requires configuration)
   - App Store Connect (via Fastlane)
   - Google Play Console (via Fastlane)

## Test Tiers

### Core Tier (Every Push/PR)
**Target**: <5 minutes
- 04_login_local_server
- 11_accept_friend_request  
- 12_send_friend_request
- 13_create_group
- 45_friend_request_full_lifecycle
- 48_group_full_lifecycle

### Extended Tier (Pre-merge)
**Target**: <15 minutes
- All core flows
- Multi-user flows (46-59)
- Edge case testing

### Release Tier (Weekly)
**Target**: 30-60 minutes  
- All core + extended flows
- Full UI regression testing (01-44)
- **Pre-release gauntlet (65-81)**:
  - Background/lifecycle testing
  - Stress testing with many friends/groups
  - Data persistence validation
  - Network edge cases
  - Full regression journey

## Pre-Release Gauntlet (Flows 65-81)

These intensive tests run only during release validation:

### Background & Lifecycle (65-70)
- `65_background_location_sharing` - App backgrounded location handling
- `66_app_kill_and_restore` - Complete app restart persistence
- `67_background_sync_burst` - Multiple location updates while backgrounded
- `68_app_backgrounded_friend_request` - Friend requests while backgrounded
- `69_app_backgrounded_group_invite` - Group invites while backgrounded  
- `70_rapid_app_switching` - Rapid foreground/background cycles

### Stress & Performance (71-74)
- `71_many_friends_map_load` - 8+ friends with locations on map
- `72_rapid_location_updates` - 20+ rapid location updates from one user
- `73_large_group` - Group with 10 members, all sharing locations
- `74_many_pending_invites` - 8+ friend requests + 3 group invites

### Data Integrity (75-78)
- `75_location_persistence_across_restart` - Location data survives restart
- `76_group_state_after_restart` - Group membership survives restart
- `77_settings_persistence` - All settings preserved across restart
- `78_incognito_survives_restart` - Incognito mode state persistence

### Network Edge Cases (79-80)
- `79_offline_queue` - Offline action queuing and replay
- `80_slow_sync` - Many events during slow network conditions

### Full Regression (81)
- `81_full_regression_journey` - 50+ step complete app workflow test

## Store Upload Configuration (TODO)

### Requirements for App Store Connect

1. **Apple Developer Account**
   - App Store Connect access
   - Distribution certificates
   - Provisioning profiles

2. **App Store Connect API Key**
   ```bash
   # Add to GitHub Secrets:
   APP_STORE_CONNECT_API_KEY_ID
   APP_STORE_CONNECT_API_ISSUER_ID  
   APP_STORE_CONNECT_API_KEY  # Base64 encoded .p8 file
   ```

3. **Fastlane Configuration**
   ```ruby
   # fastlane/Fastfile
   lane :release do
     deliver(
       skip_metadata: false,
       skip_screenshots: false, 
       submit_for_review: true,
       automatic_release: false
     )
   end
   ```

4. **Export Options**
   ```xml
   <!-- ios/ExportOptions.plist -->
   <key>method</key>
   <string>app-store</string>
   <key>teamID</key>
   <string>YOUR_TEAM_ID</string>
   ```

### Requirements for Google Play

1. **Google Play Console Access**
   - Developer account
   - App created in console
   - Upload keystore configured

2. **Service Account JSON**
   ```bash
   # Add to GitHub Secrets:
   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON  # Base64 encoded JSON file
   ```

3. **Fastlane Configuration**
   ```ruby
   # fastlane/Fastfile
   lane :deploy do
     supply(
       track: 'production',
       json_key_data: ENV['GOOGLE_PLAY_SERVICE_ACCOUNT_JSON'],
       package_name: 'app.mygrid.grid',
       aab: '../build/app/outputs/bundle/release/app-release.aab'
     )
   end
   ```

4. **Upload Keystore**
   ```bash
   # Add to GitHub Secrets:
   ANDROID_KEYSTORE  # Base64 encoded keystore file
   KEYSTORE_PASSWORD
   KEY_ALIAS
   KEY_PASSWORD
   ```

## Manual Release Process

To trigger a release manually:

1. Go to GitHub Actions
2. Select "Grid Release" workflow
3. Click "Run workflow"
4. Select branch (usually `main`)
5. Click "Run workflow"

## Release Artifacts

Each release produces:
- **GitHub Release** with changelog
- **IPA file** (iOS build)
- **AAB file** (Android App Bundle)  
- **Test reports** (90-day retention)
- **Debug artifacts** on failure (30-day retention)

## Troubleshooting

### Common Release Failures

1. **Build Failures**
   - Check Flutter/iOS/Android toolchain versions
   - Verify certificates and provisioning profiles

2. **Test Failures**
   - Review Maestro test logs in artifacts
   - Check Synapse test infrastructure status
   - Verify API helper scripts

3. **Store Upload Failures**
   - Validate certificates and keys
   - Check App Store Connect/Play Console status
   - Review Fastlane logs

### Emergency Release Process

If automated release fails:

1. **Manual Build**
   ```bash
   flutter build ipa --release
   flutter build appbundle --release
   ```

2. **Manual Test**
   ```bash
   ./run-maestro.sh release
   ```

3. **Manual Upload**
   ```bash
   fastlane deliver  # iOS
   fastlane supply   # Android
   ```

## Monitoring

- **GitHub Actions** - Workflow status and logs
- **Test Artifacts** - Detailed test reports
- **Release Issues** - Auto-created on pipeline failures
- **Changelog** - Auto-generated from commits

## Security

- All secrets stored in GitHub repository secrets
- Service account keys with minimal permissions
- Release artifacts publicly available in GitHub Releases
- Test infrastructure isolated from production