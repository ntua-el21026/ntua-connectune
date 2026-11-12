// Public-client OAuth helpers. Never put a Spotify client secret in the app.
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class SpotifyAuthorizationAttempt {
  final String verifier;
  final String state;
  SpotifyAuthorizationAttempt({required this.verifier, required this.state});
  factory SpotifyAuthorizationAttempt.create() {
    final random = Random.secure();
    String nonce(int bytes) => base64Url
        .encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    return SpotifyAuthorizationAttempt(verifier: nonce(32), state: nonce(24));
  }
  Uri authorizationUri({required String clientId, required Uri redirect}) {
    if (clientId.isEmpty || !redirect.hasScheme)
      throw StateError('Spotify client and redirect configuration required');
    return Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirect.toString(),
      'scope': 'user-read-playback-state user-read-currently-playing',
      'state': state,
      'code_challenge_method': 'S256',
      'code_challenge': base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', ''),
    });
  }

  String readCode(String callback, Uri redirect) {
    final uri = Uri.tryParse(callback);
    if (uri == null ||
        uri.scheme != redirect.scheme ||
        uri.host != redirect.host ||
        uri.port != redirect.port ||
        uri.path != redirect.path ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll['state']?.length != 1 ||
        uri.queryParameters['state'] != state ||
        uri.queryParameters.containsKey('error') ||
        uri.queryParametersAll['code']?.length != 1 ||
        (uri.queryParameters['code'] ?? '').isEmpty) {
      throw StateError('Spotify authorization callback was rejected');
    }
    return uri.queryParameters['code']!;
  }
}

class SpotifyAccessToken {
  final String value;
  final DateTime expiresAt;
  SpotifyAccessToken(this.value, this.expiresAt);
  bool isUsableAt(DateTime now) =>
      value.isNotEmpty &&
      now.add(const Duration(seconds: 30)).isBefore(expiresAt);
}

Future<SpotifyAccessToken> exchangeSpotifyCode(
    {required http.Client client,
    required String clientId,
    required Uri redirect,
    required String code,
    required String verifier,
    required DateTime now}) async {
  final response =
      await client.post(Uri.https('accounts.spotify.com', '/api/token'), body: {
    'client_id': clientId,
    'grant_type': 'authorization_code',
    'code': code,
    'redirect_uri': redirect.toString(),
    'code_verifier': verifier,
  }).timeout(const Duration(seconds: 15));
  if (response.statusCode != 200)
    throw StateError('Spotify code exchange failed');
  dynamic data;
  try {
    data = jsonDecode(response.body);
  } on FormatException {
    throw StateError('Invalid Spotify token response');
  }
  if (data is! Map ||
      data['access_token'] is! String ||
      (data['access_token'] as String).isEmpty ||
      data['expires_in'] is! int ||
      data['expires_in'] <= 0 ||
      data['token_type'] != 'Bearer') {
    throw StateError('Invalid Spotify token response');
  }
  return SpotifyAccessToken(data['access_token'] as String,
      now.add(Duration(seconds: data['expires_in'] as int)));
}
