'use strict';

const { createHash } = require('node:crypto');

const MAX_BODY_BYTES = 1_024;
const FRESHNESS_MS = 180_000;
const WINDOW_MS = 60_000;
const MAX_ACTOR_ATTEMPTS = 20;

class RequestError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

function isUid(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 128 &&
    !/[\/\u0000-\u001f\u007f]/u.test(value);
}

function header(req, name) {
  return typeof req.get === 'function' ? req.get(name) : req.headers?.[name.toLowerCase()];
}

function parseRequest(req) {
  if (req.method !== 'POST') throw new RequestError(405, 'method_not_allowed');
  const contentType = header(req, 'content-type');
  if (typeof contentType !== 'string' || !/^application\/json(?:\s*;|$)/i.test(contentType)) {
    throw new RequestError(415, 'json_required');
  }
  const declaredLength = header(req, 'content-length');
  if (declaredLength !== undefined) {
    if (!/^\d+$/.test(declaredLength)) throw new RequestError(400, 'invalid_request');
    if (Number(declaredLength) > MAX_BODY_BYTES) throw new RequestError(413, 'request_too_large');
  }
  let body;
  try {
    // Firebase HTTP requests expose rawBody. Parsing it also bounds the input
    // independently of Content-Length and Express's parsed body object.
    const raw = req.rawBody ?? Buffer.from(JSON.stringify(req.body));
    if (!Buffer.isBuffer(raw)) throw new RequestError(400, 'invalid_request');
    if (raw.length > MAX_BODY_BYTES) throw new RequestError(413, 'request_too_large');
    body = JSON.parse(raw.toString('utf8'));
  } catch (error) {
    if (error instanceof RequestError) throw error;
    throw new RequestError(400, 'invalid_request');
  }
  if (body === null || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).length !== 2 ||
      !Object.hasOwn(body, 'recipientUserId') || !Object.hasOwn(body, 'type') ||
      !isUid(body.recipientUserId) || !['like', 'superlike'].includes(body.type)) {
    throw new RequestError(400, 'invalid_request');
  }
  const authorization = header(req, 'authorization');
  if (typeof authorization !== 'string' || authorization.length > 8_192) {
    throw new RequestError(401, 'unauthenticated');
  }
  const match = /^Bearer (\S+)$/i.exec(authorization);
  if (!match) throw new RequestError(401, 'unauthenticated');
  return { ...body, idToken: match[1] };
}

function freshListener(snapshot, now) {
  if (!snapshot.exists) throw new RequestError(403, 'not_eligible');
  const data = snapshot.data();
  const timestamp = data?.timestamp;
  const updatedAt = typeof timestamp?.toMillis === 'function' ? timestamp.toMillis() : NaN;
  const point = data?.geo?.geopoint;
  if (!Number.isFinite(updatedAt) || updatedAt > now || now - updatedAt > FRESHNESS_MS ||
      !point || !Number.isFinite(point.latitude) || !Number.isFinite(point.longitude) ||
      Math.abs(point.latitude) > 90 || Math.abs(point.longitude) > 180) {
    throw new RequestError(403, 'not_eligible');
  }
  return data;
}

function distanceKm(first, second) {
  const radians = Math.PI / 180;
  const latDelta = (second.latitude - first.latitude) * radians;
  const lonDelta = (second.longitude - first.longitude) * radians;
  const haversine = Math.sin(latDelta / 2) ** 2 +
    Math.cos(first.latitude * radians) * Math.cos(second.latitude * radians) *
    Math.sin(lonDelta / 2) ** 2;
  return 6_371 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, haversine))));
}

function stateId(parts) {
  return createHash('sha256').update(JSON.stringify(parts)).digest('hex');
}

function actorAttempts(snapshot, now) {
  if (!snapshot.exists) return [];
  const attempts = snapshot.data()?.attemptsMs;
  if (!Array.isArray(attempts) || attempts.length > MAX_ACTOR_ATTEMPTS ||
      attempts.some((time) => !Number.isSafeInteger(time) || time < 0 || time > now)) {
    throw new Error('invalid persisted actor throttle state');
  }
  return attempts.filter((time) => now - time < WINDOW_MS);
}

async function reserveNotification({ db, clock }, actorUid, recipientUid, type) {
  const actorRef = db.collection('listening_data').doc(actorUid);
  const recipientRef = db.collection('listening_data').doc(recipientUid);
  const actorLimitRef = db.collection('notification_actor_limits').doc(stateId([actorUid]));
  const pairLimitRef = db.collection('notification_pair_limits').doc(stateId([actorUid, recipientUid, type]));

  return db.runTransaction(async (transaction) => {
    // A retry reads current eligibility and both durable rate limits again.
    // All reads precede writes, and provider sends occur only after commit.
    const [actorSnapshot, recipientSnapshot, actorLimit, pairLimit] = await Promise.all([
      transaction.get(actorRef), transaction.get(recipientRef),
      transaction.get(actorLimitRef), transaction.get(pairLimitRef),
    ]);
    const now = clock();
    if (!Number.isSafeInteger(now) || now < 0) throw new Error('invalid server clock');
    const actor = freshListener(actorSnapshot, now);
    const recipient = freshListener(recipientSnapshot, now);
    if (distanceKm(actor.geo.geopoint, recipient.geo.geopoint) > 0.5) {
      throw new RequestError(403, 'not_eligible');
    }
    if (typeof recipient.fcmToken !== 'string' || recipient.fcmToken.length > 4_096 ||
        !/^\S+$/u.test(recipient.fcmToken) || typeof recipient.song !== 'string' ||
        recipient.song.trim().length === 0 || recipient.song.length > 200 ||
        /[\u0000-\u001f\u007f]/u.test(recipient.song)) {
      throw new RequestError(403, 'not_eligible');
    }
    const attempts = actorAttempts(actorLimit, now);
    if (pairLimit.exists) {
      const lastAttempt = pairLimit.data()?.lastAttemptMs;
      if (!Number.isSafeInteger(lastAttempt) || lastAttempt < 0 || lastAttempt > now) {
        throw new Error('invalid persisted pair throttle state');
      }
      if (now - lastAttempt < WINDOW_MS) throw new RequestError(429, 'rate_limited');
    }
    if (attempts.length >= MAX_ACTOR_ATTEMPTS) throw new RequestError(429, 'rate_limited');
    transaction.set(actorLimitRef, { attemptsMs: [...attempts, now] });
    transaction.set(pairLimitRef, { lastAttemptMs: now });

    const superlike = type === 'superlike';
    return {
      token: recipient.fcmToken,
      notification: {
        title: superlike ? 'New super like' : 'New like',
        body: `Someone nearby ${superlike ? 'super liked' : 'liked'} your song: ${recipient.song.trim()}.`,
      },
      data: superlike ? { type, userId: actorUid } : { type },
      android: { notification: { channelId: 'superlike_channel' } },
    };
  });
}

function createNotificationHandler({ auth, db, messaging, clock = Date.now }) {
  return async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const { recipientUserId, type, idToken } = parseRequest(req);
      let actorUid;
      try {
        const decoded = await auth.verifyIdToken(idToken, true);
        actorUid = decoded?.uid;
      } catch {
        throw new RequestError(401, 'unauthenticated');
      }
      if (!isUid(actorUid)) throw new RequestError(401, 'unauthenticated');
      if (actorUid === recipientUserId) throw new RequestError(403, 'not_eligible');
      const message = await reserveNotification({ db, clock }, actorUid, recipientUserId, type);
      // A committed reservation remains consumed if FCM fails or the process
      // stops here. This prevents retries from bypassing duplicate protection.
      await messaging.send(message);
      return res.status(202).json({ accepted: true });
    } catch (error) {
      const known = error instanceof RequestError;
      if (known && error.status === 405) res.set('Allow', 'POST');
      if (known && error.status === 429) res.set('Retry-After', '60');
      return res.status(known ? error.status : 503).json({
        error: known ? error.code : 'notification_unavailable',
      });
    }
  };
}

module.exports = { createNotificationHandler };
