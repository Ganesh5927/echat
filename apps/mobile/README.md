# eChat mobile app

The Flutter client provides first-run identity onboarding, local contact trust
management, one-to-one conversations, identity and security information,
Settings, and a local user profile.

## Android setup and builds

The Android host is generated with Flutter 3.44.6 and uses Kotlin, Android
Gradle Plugin 9.0.1, Gradle 9.1, JDK 17, and the compile/target/minimum SDK
values supplied by that Flutter SDK. Install the matching Android SDK/build
tools and accept licenses using `flutter doctor --android-licenses`, then run:

```powershell
cd apps/mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release
```

APK output is `build/app/outputs/flutter-apk/app-debug.apk` or
`app-release.apk`. The release variant currently uses Flutter's generated
debug signing configuration for development/device testing only. Production
distribution requires a separately managed release key and protected signing
configuration; do not reuse or commit a development/debug key.

The Android manifest requests only `INTERNET`, needed for configured HTTPS
relay requests. Gallery selection uses the platform image-picker UI and does
not request broad media/library permissions. Camera and notification
permissions are not requested because those features are unavailable.

To configure a relay origin at build time, pass a credential-free HTTPS origin:

```powershell
flutter build apk --release --dart-define=ECHAT_RELAY_ORIGIN=https://relay.example
```

The value must be an HTTPS origin without a path, query, or embedded
credentials. It is configuration, not a secret. No session-exchange gateway is
configured by this app composition: real two-device session establishment
also requires an application-provided `SessionExchangeGateway` that safely
delivers the existing signed session initiation and response messages to the
verified peer. The relay's encrypted message-packet API does not deliver these
session-control messages.

## Identity and contacts

The Identity screen renders the validated public identity payload as a QR code
and lets the user copy that public payload. Contacts can be added by pasting the
payload; the existing trust service validates its schema and fingerprint and
keeps imported contacts unverified until the fingerprint is independently
compared. Contact display names are local encrypted metadata and do not change
the device ID, public key, fingerprint, or trust state.

Contact and conversation search runs against locally loaded contact fields and
conversation summaries/recent message previews. Search terms and message text
are not submitted to the relay; this is not a full historical message index.

## Local profile

The display name and optional gallery avatar are stored only on the device in
an AES-GCM encrypted local profile record, using the app's existing local
storage key provider. Profile changes do not alter the cryptographic device
identity and are not uploaded to the relay. Avatars are limited to 512 KB after
image selection/compression.

In temporary/in-memory mode, the profile record is also kept only in memory
and may be lost when the app restarts.

## Appearance

Appearance preferences support System default, Light, Dark, and AMOLED modes,
with Blue, Cyan, Purple, and Green accents. Choices apply immediately and are
stored locally in `SharedPreferences`; these preferences are presentation
settings, not secrets.

## Current limitations

- Public identity QR display, clipboard export, and strict paste/import are
  implemented. Camera scanning is not implemented; completing scanner support requires
  creating/configuring native hosts, adding a maintained scanner plugin,
  requesting camera permission, and validating on physical/simulated target
  platforms. A scanner must pass decoded text through the existing validated
  identity import path; it must not trust arbitrary scanned contents. The app
  does not present a camera scanner as available.
- Relay use requires an HTTPS origin configured with `ECHAT_RELAY_ORIGIN`.
- Relay UI state distinguishes unconfigured, unavailable, connecting,
  authenticating, authentication failure, and authenticated connection states
  reported by the transport. A successful health check alone is not shown as
  authenticated.
- The app's session-exchange gateway is not configured by default, so session
  establishment needs an existing supported exchange path.
- Notifications are unavailable in this build; no notification switch or
  enabled state is presented. Local notification support needs native host
  configuration and platform permission handling. Remote push additionally
  requires a push provider/backend, platform credentials, and native setup.
- Synchronization is foreground-only and initiated from the Conversations
  screen. Background execution is not configured; implementing it requires
  native hosts and platform-specific scheduling constraints. No background
  sync state is implied.
- Android SDK/build tools are available in the current development
  environment, but no physical Android device or running emulator is connected.
  APK compilation and gallery-picker behavior still need target-device
  validation.
- There is no iOS host project.
- The project-specific protocol composition has not been independently
  audited and is not production-approved.
