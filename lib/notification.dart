/// Client notification delivery is disabled until a trusted server exists.
///
/// A mobile application cannot hold Firebase Admin credentials. Receiving FCM
/// messages remains supported, but this prototype has no authorized send API.
class FCMService {
  static const bool isAvailable = false;

  /// Returns false without making a network request or claiming delivery.
  /// Retains the interaction interface while the server contract is specified.
  static Future<bool> sendNotification({
    required String token,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    return false;
  }
}
