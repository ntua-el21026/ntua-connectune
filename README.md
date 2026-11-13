# ConnecTune

ConnecTune is an NTUA ECE Human–Computer Interaction course prototype
(Autumn 2025) for discovering nearby listeners and interacting with their music.
The Flutter client combines Firebase authentication, Spotify login and playback
metadata, location-based Firestore queries, profiles, and camera-based super likes.

## HCI workflows and implementation status

The prototype explores nearby music discovery and gesture-based interaction:

1. Register or sign in with Firebase email/password authentication; use the
   password-reset screen when needed.
2. Connect Spotify, allow location access, and play a track in Spotify. Home
   requests the current playback metadata, publishes a Firestore listening
   record, and queries listeners within 0.5 km. Records must be recent; refresh
   runs on a three-minute timer.
3. Open a listener's song screen. Rotate the record artwork left to record a
   like, or right to capture/upload a camera photo and record a super like.
4. Inspect incoming super-like images, edit the profile name, or sign out.

| Area | Implemented path | Remaining dependency |
|---|---|---|
| Authentication/profile | Firebase Auth and Firestore reads/writes | Development project, enabled email/password provider, access rules |
| Discovery | Spotify current-playback request plus geospatial Firestore query | Spotify playback, valid OAuth session, location permission, other recent listeners |
| Likes/super likes | Firestore updates, Storage photo upload, gesture UI | Database/storage policy and device camera qualification |
| Push notification | HTTPS client and trusted Firebase handler | Endpoint deployment/configuration and real device delivery remain unverified |

Discovery and likes are service-backed code, not a bundled offline simulation.
Offline tests fake service boundaries. An empty nearby list is possible when no
eligible listener is publishing; sample Spotify users or location histories are
not supplied. Playback controls, a music-streaming engine, and production social
network operation are not established by the metadata/interaction screens.

## Application structure

- `lib/auth/`: Firebase sign-up, login, and password reset.
- `lib/spotify.dart`, `lib/home.dart`: Spotify authorization and nearby listening.
- `lib/song.dart`, `lib/super_like_notification_page.dart`: interaction screens.
- `lib/notification.dart`: Firebase-user-authenticated notification transport.
- `functions/`: local trusted notification handler and offline tests.
- `lib/main.dart`: startup, incoming FCM messages, and navigation.

## Local setup

Use a Flutter SDK compatible with the Dart `^3.5.4` constraint in `pubspec.yaml`.
Flutter 3.24.5 / Dart 3.5.4 was used for the bounded maintenance validation.
`pubspec.lock` retains the compatible resolved versions; `crypto` is a direct
dependency for Spotify PKCE. No Admin-auth dependency is needed in the client.

```bash
flutter pub get
flutter analyze
flutter test
flutter build bundle --debug
```

Before running, configure **your own development Firebase project** and Spotify
application/redirect URI. Replace generated Firebase platform configuration and
`lib/firebase_options.dart` together, enable the required Auth/Firestore/Storage/
Messaging services, and review access rules before using any personal data.
Android/iOS location, camera, and notification
permissions also require device testing. Desktop support is not validated.

The Dart package remains `listen_around`; imports and native callback names use
that historical application identifier. Clone the canonical repository name:

```bash
git clone https://github.com/ntua-el21026/ntua-connectune.git
cd ntua-connectune
```

After configuring the development project and callback, launch on a
supported device with public client configuration and the qualified endpoint:

```bash
flutter devices
flutter run \
  --dart-define=SPOTIFY_CLIENT_ID=your-public-client-id \
  --dart-define=SPOTIFY_REDIRECT_URI=your-registered-redirect-uri \
  --dart-define=NOTIFICATION_API_URL=https://your-owned-host/notification-endpoint
```

The values are configuration examples, not working service addresses. Omitting
`NOTIFICATION_API_URL` leaves notification transport unavailable while recorded
interactions retain their documented behavior. No privileged Firebase credential
or Spotify client secret belongs in Dart defines, assets, or platform files.
The repository contains Flutter platform scaffolds and image assets; it does
not contain Firebase rules or a ready-to-use deployed notification endpoint.

## Spotify and device setup

Spotify authorization uses the public-client Authorization Code + PKCE flow,
with callback-state validation and an expiry-bound token stored per Firebase UID.
Configure `SPOTIFY_CLIENT_ID` and `SPOTIFY_REDIRECT_URI` using Flutter Dart defines.
The redirect must be supported and registered by Spotify and matched by the
Android/iOS callback configuration. Existing native callback entries use the
`listen-around` scheme; HTTPS redirects require the corresponding app/universal
link setup.
The retired implicit grant is not used. An expired or rejected token offers
explicit reconnection rather than leaving stale listeners visible.

Auth preserves password bytes, provides password-reset navigation and clears the
navigation stack on logout. Location refresh rebuilds the nearby query. Missing
messaging tokens do not block discovery, and legacy likes values are normalized.
Logout attempts presence invalidation before sign-out; if unavailable, the old
presence may remain discoverable until the existing three-minute freshness limit.

## Notification boundary and exact status

The earlier permanently unavailable sender has been replaced by an authenticated
HTTPS client and a minimal trusted Firebase function. Likes and super likes are
recorded before a push attempt; a delivery failure does not undo the interaction.
Super-like writes use one Firestore batch. Camera cancellation and failed writes
allow retry. Incoming taps tolerate malformed data and wait for authenticated
Home navigation; cold-start FCM/local taps are also handled.

Set `NOTIFICATION_API_URL` to your HTTPS function endpoint to enable the client path. The UI distinguishes an unavailable endpoint,
an unconfirmed request and server/FCM acceptance. Acceptance does not prove a
phone displayed the notification.

The [backend](functions/README.md) verifies Firebase user ID tokens, derives
recipient tokens and messages from fresh nearby listening records, and applies
transactional rate limits. It uses the server runtime's managed identity. The
client contains no Admin key or privileged FCM signing. Existing project services,
runtime identity, endpoint configuration, Firestore ownership/throttle rules and
native permissions require integration and device testing.

## Recorded validation — 12 November 2026

- Flutter 3.24.5: 28 tests passed, including PKCE, discovery normalization,
  reset navigation and notification transport/persistence behavior.
- `flutter build bundle --debug --no-pub` passed. This is a Flutter asset/kernel
  bundle, not an Android APK or iOS archive.
- `flutter analyze --no-pub` executed with no errors; it returned exit 1 for
  retained warnings/style findings. It is not reported as a clean analyzer pass.
- Node 22.23.5: 22 backend handler tests and syntax checks passed. External Auth,
  Firestore and FCM boundaries are faked in these tests; production concurrency,
  rules, provider acceptance and device delivery are unverified.
- `python3 scripts/check_client_security.py` retains three client source-policy
  checks; these complement executable tests and do not establish device security.

On 13 November 2026, `node --test functions/test/*.test.js`
passed 22 offline tests (0 failures, 0 skipped), and
`python3 scripts/check_client_security.py` passed its three static checks.
