import 'package:flutter_test/flutter_test.dart';
import 'package:listen_around/notification.dart';

void main() {
  test('an unconfigured backend is not reported as accepted', () async {
    expect(
        await FCMService.sendNotification(
            recipientUserId: 'recipient', type: 'like'),
        NotificationDelivery.unavailable);
  });
  test('UI keeps an unconfirmed push distinct from a persisted interaction',
      () {
    expect(notificationOutcome('Like', NotificationDelivery.failed),
        contains('not confirmed'));
    expect(notificationOutcome('Like', NotificationDelivery.unavailable),
        contains('configured trusted backend'));
  });
}
