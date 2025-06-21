import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';

class FCMService {
  static AccessToken? _accessToken;
  static ServiceAccountCredentials? _credentials;

  /// Initialize the service with your service account JSON file
  static Future<void> initialize(String jsonString) async {
    final Map<String, dynamic> serviceAccount = json.decode(jsonString);
    _credentials = ServiceAccountCredentials.fromJson({
      "type": serviceAccount["type"],
      "project_id": serviceAccount["project_id"],
      "private_key_id": serviceAccount["private_key_id"],
      "private_key": serviceAccount["private_key"],
      "client_email": serviceAccount["client_email"],
      "client_id": serviceAccount["client_id"],
      "auth_uri": serviceAccount["auth_uri"],
      "token_uri": serviceAccount["token_uri"],
      "auth_provider_x509_cert_url": serviceAccount["auth_provider_x509_cert_url"],
      "client_x509_cert_url": serviceAccount["client_x509_cert_url"],
    });
  }

  /// Get a valid access token, refreshing if necessary
  static Future<String> _getAccessToken() async {
    if (_credentials == null) {
      throw Exception('FCMService not initialized. Call initialize() first.');
    }

    if (_accessToken?.hasExpired ?? true) {
      final client = await clientViaServiceAccount(
        _credentials!,
        ['https://www.googleapis.com/auth/firebase.messaging'],
      );
      _accessToken = client.credentials.accessToken;
      client.close();
    }

    return _accessToken!.data;
  }

  /// Send a notification using FCM v1 API
  static Future<bool> sendNotification({
    required String token,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      final projectId = "listen-around";


      final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

      final payload = {
        'message': {
          'token': token,
          'notification': {
            'title': title,
            'body': body,
          },
          if (data != null) 'data': data,
          "android": {"priority": "high"},
          "apns": {
            "headers": {"apns-priority": "10"}
          }
        }
      };

      final response = await http.post(
        url,
        headers: headers,
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        print('Notification sent successfully: ${response.body}');
        return true;
      } else {
        print('Failed to send notification: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error sending notification: $e');
      return false;
    }
  }
}
