import 'package:flutter_test/flutter_test.dart';
import 'package:listen_around/notification.dart';

void main() {
  test('sending is unavailable without a trusted notification server', () {
    expect(FCMService.isAvailable, isFalse);
  });

  test('an interaction cannot claim notification delivery', () async {
    final delivered = await FCMService.sendNotification(
      token: 'test-recipient',
      title: 'Like',
      body: 'Test interaction',
      data: {'type': 'like'},
    );
    expect(delivered, isFalse);
  });
}
