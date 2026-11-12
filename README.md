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
- `lib/notification.dart`: explicitly unavailable outbound notification interface.
- `lib/main.dart`: startup, incoming FCM messages, and navigation.

## Local setup

Use a Flutter SDK compatible with the Dart `^3.5.4` constraint in `pubspec.yaml`.
`pubspec.lock` records the existing dependency resolution; Flutter must refresh
and validate it after the removed Admin-auth dependency.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Before running, configure **your own development Firebase project** and Spotify
application/redirect URI. Replace generated Firebase platform configuration and
`lib/firebase_options.dart` together, enable the required Auth/Firestore/Storage/
Messaging services, and review access rules before using any personal data.
The shipped configuration identifies the historical shared project and does not
establish permission to access it. Android/iOS location, camera, and notification
permissions also require device testing. Desktop support is not validated.

## Notification boundary and status

Outbound like/super-like push delivery is disabled and always reports `false`.
The UI distinguishes a recorded interaction from an unavailable notification.
Receiving FCM messages and local notification presentation remain in the client.
A Firebase Admin credential previously bundled as an asset has been removed from
the working tree and startup path, along with service-account signing code.
**The credential owner must revoke the exposed key; local deletion does not
remove previous Git history, downloaded applications, or remote copies.**

Re-enabling delivery requires a separately implemented trusted server. It must
verify Firebase user ID tokens, authorize the interaction and recipient, derive
the message/recipient server-side, rate-limit requests, and keep all Admin
credentials outside the application. No such server is included. Do not put a
service-account JSON file, private key, or privileged FCM access token in assets,
Dart defines, or client code. Existing Firestore writes are prototype behavior;
server rules and user consent still require review.

## Validation

`python3 scripts/check_client_security.py` performs three source-policy checks:
no client private-key material, no startup credential loading, and no privileged
FCM sender. These checks were observed failing before removal and passing after.
`test/notification_test.dart` replaces the unrelated counter template with tests
of unavailable delivery. Flutter/Dart were unavailable during the November 2026
local preparation, so analysis, Dart tests, device flows, and provider integration
were **not executed**. Source checks do not demonstrate runtime correctness.

## Attribution and reuse

This is team coursework, preserved as a project artifact. The imported history
and code do not establish each member's implementation responsibilities; no
exclusive individual authorship is claimed. The root [MIT license](LICENSE)
applies to material the contributors have authority to license. Course materials,
images, provider assets, and third-party packages retain their respective rights.
Provider credentials, location histories, profiles, and personal images are not
portfolio demonstration data.
