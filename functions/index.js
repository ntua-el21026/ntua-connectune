'use strict';

const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { onRequest } = require('firebase-functions/v2/https');
const { createNotificationHandler } = require('./notification-handler');

// The deployed runtime supplies its managed identity. No key file, service
// account JSON, or caller-supplied credential is loaded by this server.
initializeApp();

exports.sendInteractionNotification = onRequest(
  { cors: false, timeoutSeconds: 15, memory: '256MiB', maxInstances: 3 },
  createNotificationHandler({ auth: getAuth(), db: getFirestore(), messaging: getMessaging() }),
);
