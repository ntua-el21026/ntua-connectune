# Local notification backend

This directory contains a minimal Firebase HTTPS notification implementation for
ConnecTune. It has offline handler tests.

The exported function is `sendInteractionNotification`. Its runtime target is
Node.js 22. `firebase-admin` 13.6.1 and `firebase-functions` 7.0.5 are pinned in
`package.json` and the lockfile.

## Request and response

Send an HTTPS `POST` with `Content-Type: application/json` and
`Authorization: Bearer <Firebase user ID token>`. The JSON object has exactly two
fields:

```json
{"recipientUserId":"recipient-uid","type":"like"}
```

`type` is `like` or `superlike`. The caller cannot supply an FCM token, sender
identity, title, body, or extra data. The handler accepts at most 1,024 body bytes
and checks the ID token with revocation checking enabled. UIDs have 1–128
characters and contain no slash or control character.

After FCM accepts the send call, the response is HTTP 202 with
`{"accepted":true}`. This reports provider acceptance, not device delivery.
Failures return a non-2xx status and `{"error":"<code>"}`. Unsupported methods
return 405, malformed input returns 400/413/415, unauthenticated requests return
401, ineligible interactions return 403, throttle rejection returns 429, and
database or messaging failures return 503. Internal provider errors, tokens, and
message IDs are not returned.

## Server decisions and persisted limits

The verified token supplies the actor UID. The handler rejects self-notification
and reads both `listening_data/{actorUid}` and `listening_data/{recipientUid}` in
a Firestore transaction. Both records need a Firestore `timestamp` no more than
180 seconds old, no future timestamp, and valid numeric `geo.geopoint`
coordinates within 0.5 km of one another. The recipient record supplies its
existing `fcmToken` and `song` fields. Messages and data fields are constructed
on the server; a superlike's `userId` is the verified actor UID.

The same transaction reserves two durable limits:

- `notification_actor_limits/{hash}` stores up to 20 attempt timestamps for a
  rolling 60-second window per actor.
- `notification_pair_limits/{hash}` stores the most recent reservation for each
  actor, recipient, and type, allowing one reservation per 60 seconds.

Document IDs are SHA-256 hashes of the corresponding UID tuple. All transaction
reads precede writes. FCM is called after the transaction commits, so transaction
retries cannot repeat a provider send. A provider failure or process interruption
after reservation consumes the limit; a retry may return 429. This conservative
behavior does not provide exactly-once delivery or an atomic database/FCM commit.
There is no automatic retry worker or throttle-record cleanup job.

## Runtime prerequisites and limitations

`index.js` initializes Firebase Admin through the deployed runtime's managed
identity. It loads no key file or client-supplied Admin credential. Deployment,
runtime IAM, FCM configuration, endpoint configuration in the client, and device
notification behavior still require integration testing with a development project.

The deployment must protect listening-record ownership and allow only trusted
server code to write throttle collections. In particular, a user must not be able
to replace another user's destination token, timestamp, or coordinates, or reset
rate-limit documents. Those Firestore rules are not supplied or validated here.
Presence timestamps must be server timestamps. Location eligibility uses
reported coordinates and does not attest physical proximity. Integration tests must cover these requirements before enabling an endpoint.

## Local validation

Run with Node.js 22:

```bash
npm ci --ignore-scripts
npm test
npm run check
```

The tests execute the real request handler and fake only the external Auth,
Firestore, and FCM boundaries. They check input rejection, verified identity,
record freshness and geometry, payload derivation, persisted rate decisions,
callback retries, and provider errors. The in-memory transaction fake does not
qualify Firestore concurrency, deployment identity, actual token revocation,
FCM delivery, or access rules. No provider is contacted by these tests.

The implementation follows Firebase's documented
[ID-token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens),
[Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions),
[Admin messaging](https://firebase.google.com/docs/cloud-messaging/send/admin-sdk),
and [HTTPS function wrapper](https://firebase.google.com/docs/functions/http-events).
