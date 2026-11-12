/// Date-keyed like counts; legacy numeric totals cannot identify a day's count.
Map<String, dynamic> normalizedDailyLikes(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  return <String, dynamic>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

num dailyLikeCount(Object? value, String date) {
  final count = normalizedDailyLikes(value)[date];
  return count is num ? count : 0;
}

/// Converts a live presence record into the existing nearby-listener UI data.
Map<String, dynamic>? discoveryListener({
  required String userId,
  required Map<String, dynamic>? data,
  required String? currentUserId,
  required DateTime now,
  required DateTime? updatedAt,
}) {
  if (data == null ||
      (currentUserId != null &&
          (userId == currentUserId || data['userId'] == currentUserId)) ||
      updatedAt == null ||
      now.difference(updatedAt).inSeconds > 180) {
    return null;
  }

  final date = '${now.year}-${now.month}-${now.day}';
  return <String, dynamic>{
    'userId': userId,
    'song': data['song'] ?? 'Unknown Song',
    'artistName': data['artistName'] ?? 'Unknown Artist',
    'previewUrl': data['previewUrl'],
    'imageUrl': data['imageUrl'] ?? '',
    'fcmToken': data['fcmToken'] ?? '',
    'name': data['name'] ?? 'Unknown User',
    'likes': dailyLikeCount(data['likes'], date),
  };
}
