# ConnecTune

ConnecTune is an NTUA ECE Human–Computer Interaction course prototype
(Autumn 2025) for discovering nearby listeners and interacting with their music.
The Flutter client combines Firebase authentication, Spotify login and playback
metadata, location-based Firestore queries, profiles, and camera-based super likes.
It is a coursework prototype; provider configuration and backend policy are part
of the setup, rather than evidence of an independently deployable service.

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
The shipped configuration identifies the historical shared project and does not
establish permission to access it. Android/iOS location, camera, and notification
permissions also require device testing. Desktop support is not validated.

## Spotify and device setup

Spotify authorization uses the public-client Authorization Code + PKCE flow,
with callback-state validation and an expiry-bound token stored per Firebase UID.
Configure `SPOTIFY_CLIENT_ID` and `SPOTIFY_REDIRECT_URI` using Flutter Dart defines.
The redirect must be supported and registered by Spotify and matched by the
Android/iOS callback configuration. Existing native callback entries use the
`listen-around` scheme; HTTPS redirects require the corresponding app/universal
link setup. No redirect or live OAuth integration was qualified in this pass.
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

**No endpoint was deployed or configured, so real push delivery is not restored
end to end.** Set `NOTIFICATION_API_URL` to the owned, qualified HTTPS function
endpoint to enable the client path. The UI distinguishes an unavailable endpoint,
an unconfirmed request and server/FCM acceptance. Acceptance does not prove a
phone displayed the notification.

The [backend](functions/README.md) verifies Firebase user ID tokens, derives
recipient tokens and messages from fresh nearby listening records, and applies
transactional rate limits. It uses the server runtime's managed identity. The
client contains no Admin key or privileged FCM signing. Existing project services,
runtime identity, endpoint configuration, Firestore ownership/throttle rules and
native permissions must be qualified before deployment. No such deployment,
provider test, rule change or credential operation occurred here.

Known exposed material was removed from the prepared current source within the
documented inspection scope. Provider revocation/rotation is **owner-deferred and
not confirmed**. Original Git history remains intact and may retain old values.
Do not restore administrative material to the client.

## Bounded validation — 12 November 2026

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

No live Firebase login, Spotify callback, GPS/camera operation or push delivery
was exercised. Android SDK/device and Apple build/signing environments are not
available here. Existing research and other portfolio test receipts are reused
for unchanged code; this pass adds no portfolio-wide audit or model evaluation.

## Attribution and reuse

This is team coursework, preserved as a project artifact. The imported history
and code do not establish each member's implementation responsibilities; no
exclusive individual authorship is claimed. The root [MIT license](LICENSE)
applies to material the contributors have authority to license. Course materials,
images, provider assets, and third-party packages retain their respective rights.
Provider credentials, location histories, profiles, and personal images are not
portfolio demonstration data.
