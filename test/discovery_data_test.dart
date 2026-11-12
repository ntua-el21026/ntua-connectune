import 'package:flutter_test/flutter_test.dart';
import 'package:listen_around/discovery_data.dart';

void main() {
  final now = DateTime(2026, 11, 12, 12);
  const date = '2026-11-12';
  const track = <String, dynamic>{
    'song': 'Test song',
    'artistName': 'Test artist',
    'imageUrl': 'https://example.test/cover.jpg',
    'name': 'Nearby listener',
  };

  group('daily likes', () {
    test('normalizes missing and legacy numeric likes to an empty map', () {
      expect(normalizedDailyLikes(null), isEmpty);
      expect(normalizedDailyLikes(0), isEmpty);
      expect(normalizedDailyLikes(7), isEmpty);
      expect(dailyLikeCount(null, date), 0);
      expect(dailyLikeCount(7, date), 0);
    });

    test('keeps counts on their original dates', () {
      const likes = <String, dynamic>{
        '2026-11-11': 3,
        date: 2,
      };

      expect(normalizedDailyLikes(likes), likes);
      expect(dailyLikeCount(likes, date), 2);
      expect(dailyLikeCount(likes, '2026-11-11'), 3);
      expect(dailyLikeCount(likes, '2026-11-10'), 0);
    });

    test('ignores a nonnumeric daily count', () {
      expect(dailyLikeCount({date: 'unavailable'}, date), 0);
    });
  });

  group('nearby discovery records', () {
    test('retains new listeners alongside listeners with dated likes', () {
      final likesByUser = <String, Object?>{
        'new-listener': null,
        'legacy-listener': 0,
        'liked-listener': {date: 4},
      };
      final listeners = likesByUser.entries
          .map((entry) => discoveryListener(
                userId: entry.key,
                data: {...track, 'likes': entry.value},
                currentUserId: 'current-user',
                now: now,
                updatedAt: now,
              ))
          .whereType<Map<String, dynamic>>()
          .toList();

      expect(listeners.map((listener) => listener['userId']), likesByUser.keys);
      expect(listeners.map((listener) => listener['likes']), [0, 0, 4]);
      expect(listeners.map((listener) => listener['song']),
          everyElement('Test song'));
    });

    test('a missing messaging token does not block a listener interaction', () {
      final listener = discoveryListener(
        userId: 'nearby-user',
        data: {...track, 'fcmToken': null},
        currentUserId: 'current-user',
        now: now,
        updatedAt: now,
      );

      expect(listener, isNotNull);
      expect(listener!['fcmToken'], '');
      expect(listener['name'], 'Nearby listener');
    });

    test('keeps an available messaging token', () {
      final listener = discoveryListener(
        userId: 'nearby-user',
        data: {...track, 'fcmToken': 'test-token'},
        currentUserId: 'current-user',
        now: now,
        updatedAt: now,
      );

      expect(listener!['fcmToken'], 'test-token');
    });

    test('uses a display fallback when a listener name is absent', () {
      final listener = discoveryListener(
        userId: 'nearby-user',
        data: {...track, 'name': null},
        currentUserId: 'current-user',
        now: now,
        updatedAt: now,
      );

      expect(listener!['name'], 'Unknown User');
    });

    test('excludes the current user by document identity', () {
      expect(
        discoveryListener(
          userId: 'current-user',
          data: track,
          currentUserId: 'current-user',
          now: now,
          updatedAt: now,
        ),
        isNull,
      );
    });

    test('excludes the current user by stored identity', () {
      expect(
        discoveryListener(
          userId: 'legacy-document',
          data: {...track, 'userId': 'current-user'},
          currentUserId: 'current-user',
          now: now,
          updatedAt: now,
        ),
        isNull,
      );
    });

    test('excludes absent records and unresolved server timestamps', () {
      expect(
        discoveryListener(
          userId: 'nearby-user',
          data: null,
          currentUserId: 'current-user',
          now: now,
          updatedAt: now,
        ),
        isNull,
      );
      expect(
        discoveryListener(
          userId: 'nearby-user',
          data: track,
          currentUserId: 'current-user',
          now: now,
          updatedAt: null,
        ),
        isNull,
      );
    });

    test('excludes expired presence and retains the freshness boundary', () {
      Map<String, dynamic>? atAge(int seconds) => discoveryListener(
            userId: 'nearby-user',
            data: track,
            currentUserId: 'current-user',
            now: now,
            updatedAt: now.subtract(Duration(seconds: seconds)),
          );

      expect(atAge(180), isNotNull);
      expect(atAge(181), isNull);
    });
  });
}
