import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:listen_around/notification.dart';

void main() {
  test('unconfigured sender makes no authenticated or network request',
      () async {
    final sender = NotificationSender(
        endpoint: null,
        idToken: () async => throw StateError('must not request an identity'),
        client: MockClient(
            (_) async => throw StateError('must not contact a server')));
    expect(await sender.send(recipientUserId: 'recipient', type: 'like'),
        NotificationDelivery.unavailable);
  });
  test(
      'configured sender uses Firebase identity and recipient IDs without privileged payloads',
      () async {
    final sender = NotificationSender(
        endpoint: Uri.parse('https://example.test/sendInteractionNotification'),
        idToken: () async => 'synthetic-firebase-token',
        client: MockClient((request) async {
          expect(request.headers['Authorization'],
              'Bearer synthetic-firebase-token');
          expect(jsonDecode(request.body),
              {'recipientUserId': 'recipient', 'type': 'superlike'});
          return http.Response('{"accepted":true}', 202);
        }));
    expect(await sender.send(recipientUserId: 'recipient', type: 'superlike'),
        NotificationDelivery.accepted);
  });
  test('missing login and server rejection never report delivery', () async {
    final endpoint =
        Uri.parse('https://example.test/sendInteractionNotification');
    final unsigned = NotificationSender(
        endpoint: endpoint,
        idToken: () async => null,
        client: MockClient(
            (_) async => throw StateError('unauthenticated request')));
    expect(await unsigned.send(recipientUserId: 'recipient', type: 'like'),
        NotificationDelivery.failed);
    for (final reply in [
      http.Response('{"accepted":true}', 403),
      http.Response('{}', 202),
      http.Response('bad-json', 202)
    ]) {
      final sender = NotificationSender(
          endpoint: endpoint,
          idToken: () async => 'synthetic-token',
          client: MockClient((_) async => reply));
      expect(await sender.send(recipientUserId: 'recipient', type: 'like'),
          NotificationDelivery.failed);
    }
  });
  test('transport failures preserve an honest unconfirmed result', () async {
    final sender = NotificationSender(
        endpoint: Uri.parse('https://example.test/notify'),
        idToken: () async => 'synthetic-token',
        client: MockClient((_) async => throw http.ClientException('offline')));
    expect(await sender.send(recipientUserId: 'recipient', type: 'like'),
        NotificationDelivery.failed);
  });
  test('insecure nonloopback endpoints cannot receive identity tokens',
      () async {
    final sender = NotificationSender(
        endpoint: Uri.parse('http://example.test/notify'),
        idToken: () async => throw StateError('must not request identity'),
        client: MockClient((_) async => throw StateError('must not dispatch')));
    expect(await sender.send(recipientUserId: 'recipient', type: 'like'),
        NotificationDelivery.unavailable);
  });

  test('notification failure cannot erase an already recorded interaction',
      () async {
    var recorded = false;
    final result = await recordInteractionAndNotify(record: () async {
      recorded = true;
    }, notify: () async {
      expect(recorded, isTrue);
      throw StateError('synthetic delivery failure');
    });
    expect(recorded, isTrue);
    expect(result, NotificationDelivery.failed);
  });
  test('failed persistence never emits a push for an unrecorded interaction',
      () async {
    var notified = false;
    await expectLater(
        recordInteractionAndNotify(
            record: () async => throw StateError('synthetic write failure'),
            notify: () async {
              notified = true;
              return NotificationDelivery.accepted;
            }),
        throwsStateError);
    expect(notified, isFalse);
  });
  test(
      'notification routing ignores malformed, unrelated or missing sender data',
      () {
    for (final payload in [
      'not-json',
      '[]',
      '{}',
      '{"type":"like","userId":"sender"}',
      '{"type":"superlike","userId":7}'
    ]) {
      expect(superLikeSender(payload), isNull);
    }
    expect(superLikeSender('{"type":"superlike","userId":"sender"}'), 'sender');
  });

  testWidgets(
      'identity refresh timeout cannot hang a recorded notification request',
      (tester) async {
    final pendingIdentity = Completer<String?>();
    final sender = NotificationSender(
        endpoint: Uri.parse('https://example.test/notify'),
        idToken: () => pendingIdentity.future,
        client: MockClient((_) async =>
            throw StateError('must not dispatch without identity')));
    final result = sender.send(recipientUserId: 'recipient', type: 'like');
    await tester.pump(const Duration(seconds: 11));
    expect(await result, NotificationDelivery.failed);
  });
}
