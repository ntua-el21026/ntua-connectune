import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

enum NotificationDelivery { accepted, unavailable, failed }

class NotificationSender {
  final Uri? endpoint;
  final Future<String?> Function() idToken;
  final http.Client client;
  NotificationSender(
      {required this.endpoint, required this.idToken, required this.client});
  Future<NotificationDelivery> send(
      {required String recipientUserId, required String type}) async {
    final url = endpoint;
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      return NotificationDelivery.unavailable;
    }
    if (recipientUserId.isEmpty || !['like', 'superlike'].contains(type))
      return NotificationDelivery.failed;
    try {
      final token = await idToken().timeout(const Duration(seconds: 10));
      if (token == null || token.isEmpty) return NotificationDelivery.failed;
      final reply = await client
          .post(url,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(
                  {'recipientUserId': recipientUserId, 'type': type}))
          .timeout(const Duration(seconds: 10));
      if (reply.statusCode != 202) return NotificationDelivery.failed;
      final body = jsonDecode(reply.body);
      return body is Map && body['accepted'] == true
          ? NotificationDelivery.accepted
          : NotificationDelivery.failed;
    } catch (_) {
      return NotificationDelivery.failed;
    }
  }
}

class FCMService {
  static Uri? get endpoint {
    const value = String.fromEnvironment('NOTIFICATION_API_URL');
    return value.isEmpty ? null : Uri.tryParse(value);
  }

  static Future<NotificationDelivery> sendNotification(
      {required String recipientUserId, required String type}) async {
    if (endpoint == null) return NotificationDelivery.unavailable;
    final client = http.Client();
    try {
      return await NotificationSender(
        endpoint: endpoint,
        client: client,
        idToken: () async {
          final user = FirebaseAuth.instance.currentUser;
          return user == null ? null : await user.getIdToken();
        },
      ).send(recipientUserId: recipientUserId, type: type);
    } finally {
      client.close();
    }
  }
}

String notificationOutcome(String interaction, NotificationDelivery outcome) {
  switch (outcome) {
    case NotificationDelivery.accepted:
      return '$interaction recorded; push request accepted by the server.';
    case NotificationDelivery.unavailable:
      return '$interaction recorded. Push delivery needs a configured trusted backend.';
    case NotificationDelivery.failed:
      return '$interaction recorded. Push delivery was not confirmed.';
  }
}

Future<NotificationDelivery> recordInteractionAndNotify({
  required Future<void> Function() record,
  required Future<NotificationDelivery> Function() notify,
}) async {
  await record();
  try {
    return await notify();
  } catch (_) {
    return NotificationDelivery.failed;
  }
}

String? superLikeSender(String payload) {
  try {
    final data = jsonDecode(payload);
    if (data is! Map ||
        data['type'] != 'superlike' ||
        data['userId'] is! String) return null;
    final sender = data['userId'] as String;
    return sender.isNotEmpty && sender.length <= 128 && !sender.contains('/')
        ? sender
        : null;
  } on FormatException {
    return null;
  }
}
