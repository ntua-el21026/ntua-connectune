'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createNotificationHandler } = require('../notification-handler');

const START = 1_730_000_000_000;

function listener(overrides = {}) {
  return {
    fcmToken: 'recipient-device-token',
    song: 'Recipient song',
    timestamp: { toMillis: () => START - 1_000 },
    geo: { geopoint: { latitude: 37.98, longitude: 23.73 } },
    ...overrides,
  };
}

// Only provider boundaries are faked. The real handler performs validation,
// geographic eligibility, persisted throttle decisions, and payload derivation.
function harness() {
  const records = new Map([
    ['listening_data/actor-id', listener({ fcmToken: 'actor-device-token' })],
    ['listening_data/recipient-id', listener()],
  ]);
  const calls = { auth: [], messages: [], transactions: 0 };
  const controls = { now: START, authFailure: false, dbFailure: false,
    sendFailure: false, retryTransaction: false, decodedUid: 'actor-id' };
  let queue = Promise.resolve();
  const db = {
    collection(collection) {
      return { doc: (id) => ({ path: `${collection}/${id}` }) };
    },
    runTransaction(callback) {
      const execute = async () => {
        calls.transactions++;
        if (controls.dbFailure) throw new Error('database unavailable');
        const attempt = async (commit) => {
          const pending = new Map();
          const result = await callback({
            async get(ref) {
              assert.equal(pending.size, 0, 'Firestore reads must precede writes');
              return { exists: records.has(ref.path), data: () => records.get(ref.path) };
            },
            set(ref, data) { pending.set(ref.path, data); },
          });
          if (commit) for (const [path, data] of pending) records.set(path, data);
          return result;
        };
        if (controls.retryTransaction) {
          controls.retryTransaction = false;
          await attempt(false);
        }
        return attempt(true);
      };
      const operation = queue.then(execute, execute);
      queue = operation.catch(() => {});
      return operation;
    },
  };
  const dependencies = {
    auth: {
      async verifyIdToken(token, checkRevoked) {
        calls.auth.push({ token, checkRevoked });
        if (controls.authFailure || token !== 'valid-id-token') throw new Error('invalid token');
        return { uid: controls.decodedUid };
      },
    },
    db,
    messaging: {
      async send(message) {
        if (controls.sendFailure) throw new Error('provider unavailable');
        calls.messages.push(message);
        return 'provider-message-id';
      },
    },
    clock: () => controls.now,
  };
  const handler = createNotificationHandler(dependencies);
  async function request(body = { recipientUserId: 'recipient-id', type: 'like' }, options = {}) {
    const headers = { 'content-type': 'application/json',
      authorization: 'Bearer valid-id-token', ...options.headers };
    const req = { method: 'POST', body, rawBody: Buffer.from(JSON.stringify(body)),
      ...options, headers, get: (name) => headers[name.toLowerCase()] };
    const res = {
      statusCode: 200,
      headers: {},
      set(name, value) { this.headers[name] = value; return this; },
      status(code) { this.statusCode = code; return this; },
      json(payload) { this.body = payload; return this; },
    };
    await (options.handler || handler)(req, res);
    return res;
  }
  return { request, records, controls, calls, dependencies };
}

test('requires a Firebase Bearer token and checks token revocation', async () => {
  const h = harness();
  for (const authorization of [undefined, '', 'Basic password', 'Bearer invalid-token']) {
    const res = await h.request(undefined, { headers: { authorization } });
    assert.equal(res.statusCode, 401);
  }
  assert.deepEqual(h.calls.auth, [{ token: 'invalid-token', checkRevoked: true }]);
  assert.equal(h.calls.transactions, 0);
  assert.equal(h.calls.messages.length, 0);
});

test('rejects unsupported methods and non-JSON content', async () => {
  const h = harness();
  const wrongMethod = await h.request(undefined, { method: 'GET' });
  assert.equal(wrongMethod.statusCode, 405);
  assert.equal(wrongMethod.headers.Allow, 'POST');
  const wrongContent = await h.request(undefined, { headers: { 'content-type': 'text/plain' } });
  assert.equal(wrongContent.statusCode, 415);
  assert.equal(h.calls.messages.length, 0);
});

test('bounds both the actual raw JSON body and declared content length', async () => {
  const h = harness();
  assert.equal((await h.request(undefined, { rawBody: Buffer.alloc(1_025, ' ') })).statusCode, 413);
  assert.equal((await h.request(undefined, { headers: { 'content-length': '1025' } })).statusCode, 413);
  assert.equal(h.calls.auth.length, 0);
});

test('rejects invalid JSON and malformed request shapes', async () => {
  const h = harness();
  assert.equal((await h.request(undefined, { rawBody: Buffer.from('{') })).statusCode, 400);
  for (const body of [null, [], 'text', {}, { recipientUserId: 'recipient-id' },
    { recipientUserId: 'recipient-id', type: 'arbitrary' }]) {
    assert.equal((await h.request(body)).statusCode, 400);
  }
  assert.equal(h.calls.messages.length, 0);
});

test('rejects caller-controlled FCM tokens, content, identities and unknown fields', async () => {
  const h = harness();
  for (const field of ['token', 'fcmToken', 'title', 'body', 'userId', 'senderUserId', 'data', 'unexpected']) {
    const res = await h.request({ recipientUserId: 'recipient-id', type: 'like', [field]: 'forged' });
    assert.equal(res.statusCode, 400, field);
  }
  assert.equal(h.calls.messages.length, 0);
});

test('rejects path separators, controls, empty and oversized recipient IDs', async () => {
  const h = harness();
  for (const uid of ['', '/', 'users/target', 'bad\u0000id', 'a'.repeat(129)]) {
    assert.equal((await h.request({ recipientUserId: uid, type: 'like' })).statusCode, 400);
  }
  assert.equal(h.calls.transactions, 0);
});

test('rejects self-notification and invalid verified actor IDs', async () => {
  const h = harness();
  assert.equal((await h.request({ recipientUserId: 'actor-id', type: 'like' })).statusCode, 403);
  h.controls.decodedUid = 'forged/actor';
  assert.equal((await h.request()).statusCode, 401);
  assert.equal(h.calls.transactions, 0);
});

test('requires both actor and recipient listening records', async () => {
  for (const path of ['listening_data/actor-id', 'listening_data/recipient-id']) {
    const h = harness();
    h.records.delete(path);
    assert.equal((await h.request()).statusCode, 403);
    assert.equal(h.calls.messages.length, 0);
  }
});

test('rejects stale, future and absent timestamps on either listening record', async () => {
  for (const path of ['listening_data/actor-id', 'listening_data/recipient-id']) {
    for (const timestamp of [null, { toMillis: () => START - 180_001 },
      { toMillis: () => START + 1 }, { toMillis: () => NaN }]) {
      const h = harness();
      h.records.set(path, listener({ timestamp }));
      assert.equal((await h.request()).statusCode, 403);
      assert.equal(h.calls.messages.length, 0);
    }
  }
});

test('accepts records exactly 180 seconds old', async () => {
  const h = harness();
  h.records.set('listening_data/recipient-id', listener({ timestamp: { toMillis: () => START - 180_000 } }));
  assert.equal((await h.request()).statusCode, 202);
});

test('requires valid bounded numeric coordinates on both records', async () => {
  for (const path of ['listening_data/actor-id', 'listening_data/recipient-id']) {
    for (const geopoint of [null, { latitude: 91, longitude: 23 },
      { latitude: 37, longitude: -181 }, { latitude: NaN, longitude: 23 },
      { latitude: '37', longitude: 23 }]) {
      const h = harness();
      h.records.set(path, listener({ geo: { geopoint } }));
      assert.equal((await h.request()).statusCode, 403);
      assert.equal(h.calls.messages.length, 0);
    }
  }
});

test('rejects recipients outside 0.5 km and accepts one about 0.445 km away', async () => {
  const h = harness();
  h.records.set('listening_data/recipient-id', listener({ geo: { geopoint: { latitude: 37.985, longitude: 23.73 } } }));
  assert.equal((await h.request()).statusCode, 403);
  h.records.set('listening_data/recipient-id', listener({ geo: { geopoint: { latitude: 37.984, longitude: 23.73 } } }));
  assert.equal((await h.request()).statusCode, 202);
});

test('requires a usable recipient FCM token and song from persisted data', async () => {
  for (const change of [{ fcmToken: '' }, { fcmToken: 'bad token' },
    { fcmToken: 'a'.repeat(4_097) }, { song: '' }, { song: 'a'.repeat(201) }]) {
    const h = harness();
    h.records.set('listening_data/recipient-id', listener(change));
    assert.equal((await h.request()).statusCode, 403);
    assert.equal(h.calls.messages.length, 0);
  }
});

test('derives the destination and fixed like payload from server records', async () => {
  const h = harness();
  const res = await h.request();
  assert.equal(res.statusCode, 202);
  assert.deepEqual(res.body, { accepted: true });
  assert.deepEqual(h.calls.messages, [{
    token: 'recipient-device-token',
    notification: { title: 'New like', body: 'Someone nearby liked your song: Recipient song.' },
    data: { type: 'like' },
    android: { notification: { channelId: 'superlike_channel' } },
  }]);
  assert.deepEqual(h.calls.auth, [{ token: 'valid-id-token', checkRevoked: true }]);
});

test('derives the superlike sender only from verified authentication', async () => {
  const h = harness();
  const res = await h.request({ recipientUserId: 'recipient-id', type: 'superlike' });
  assert.equal(res.statusCode, 202);
  assert.deepEqual(h.calls.messages[0], {
    token: 'recipient-device-token',
    notification: { title: 'New super like', body: 'Someone nearby super liked your song: Recipient song.' },
    data: { type: 'superlike', userId: 'actor-id' },
    android: { notification: { channelId: 'superlike_channel' } },
  });
});

test('persists per-pair/type reservations across new handler instances', async () => {
  const h = harness();
  assert.equal((await h.request()).statusCode, 202);
  const restarted = createNotificationHandler(h.dependencies);
  assert.equal((await h.request(undefined, { handler: restarted })).statusCode, 429);
  assert.equal((await h.request({ recipientUserId: 'recipient-id', type: 'superlike' })).statusCode, 202);
  h.controls.now += 59_999;
  assert.equal((await h.request()).statusCode, 429);
  h.controls.now += 1;
  assert.equal((await h.request()).statusCode, 202);
  assert.equal(h.calls.messages.length, 3);
});

test('limits each actor to 20 notifications in a rolling minute', async () => {
  const h = harness();
  for (let i = 0; i < 21; i++) h.records.set(`listening_data/recipient-${i}`, listener());
  for (let i = 0; i < 20; i++) {
    assert.equal((await h.request({ recipientUserId: `recipient-${i}`, type: 'like' })).statusCode, 202);
    h.controls.now += 1_000;
  }
  assert.equal((await h.request({ recipientUserId: 'recipient-20', type: 'like' })).statusCode, 429);
  h.controls.now = START + 59_999;
  assert.equal((await h.request({ recipientUserId: 'recipient-20', type: 'like' })).statusCode, 429);
  h.controls.now = START + 60_000;
  assert.equal((await h.request({ recipientUserId: 'recipient-20', type: 'like' })).statusCode, 202);
  assert.equal(h.calls.messages.length, 21);
});

test('concurrent duplicate attempts reserve only one provider send', async () => {
  const h = harness();
  const responses = await Promise.all([h.request(), h.request()]);
  assert.deepEqual(responses.map((r) => r.statusCode).sort(), [202, 429]);
  assert.equal(h.calls.messages.length, 1);
});

test('transaction callback retries do not duplicate provider sends', async () => {
  const h = harness();
  h.controls.retryTransaction = true;
  assert.equal((await h.request()).statusCode, 202);
  assert.equal(h.calls.messages.length, 1);
});

test('fails closed on authentication and database provider errors', async () => {
  const h = harness();
  h.controls.authFailure = true;
  assert.equal((await h.request()).statusCode, 401);
  h.controls.authFailure = false;
  h.controls.dbFailure = true;
  assert.equal((await h.request()).statusCode, 503);
  assert.equal(h.calls.messages.length, 0);
});

test('does not claim acceptance when FCM fails and retains its throttle reservation', async () => {
  const h = harness();
  h.controls.sendFailure = true;
  const failed = await h.request();
  assert.equal(failed.statusCode, 503);
  assert.deepEqual(failed.body, { error: 'notification_unavailable' });
  h.controls.sendFailure = false;
  assert.equal((await h.request()).statusCode, 429);
  assert.equal(h.calls.messages.length, 0);
});

test('corrupt persisted throttle state fails closed', async () => {
  const h = harness();
  assert.equal((await h.request()).statusCode, 202);
  const path = [...h.records.keys()].find((key) => key.startsWith('notification_actor_limits/'));
  h.records.set(path, { attemptsMs: ['invalid'] });
  const res = await h.request({ recipientUserId: 'recipient-id', type: 'superlike' });
  assert.equal(res.statusCode, 503);
  assert.equal(h.calls.messages.length, 1);
});
