import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:listen_around/spotify_oauth.dart';

void main() {
  final redirect = Uri.parse('listen-around://callback');
  test('PKCE uses the RFC7636 S256 example and a code grant', () {
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    final attempt =
        SpotifyAuthorizationAttempt(verifier: verifier, state: 'expected');
    final url = attempt.authorizationUri(
        clientId: 'synthetic-client', redirect: redirect);
    expect(url.queryParameters['code_challenge'],
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    expect(url.queryParameters['response_type'], 'code');
    expect(url.queryParameters['code_challenge_method'], 'S256');
    expect(url.queryParameters['state'], 'expected');
    expect(url.queryParameters.containsKey('client_secret'), isFalse);
  });
  test('only the matching callback and state yield a code', () {
    final attempt =
        SpotifyAuthorizationAttempt(verifier: 'v' * 43, state: 'expected');
    expect(
        attempt.readCode(
            'listen-around://callback?state=expected&code=fixture', redirect),
        'fixture');
    for (final url in [
      'listen-around://callback?state=wrong&code=fixture',
      'listen-around://other?state=expected&code=fixture',
      'listen-around://callback?state=expected&code=a&code=b',
      'listen-around://callback?state=expected&error=access_denied',
      'listen-around://callback#access_token=synthetic-token',
    ]) {
      expect(() => attempt.readCode(url, redirect), throwsStateError);
    }
  });
  test('secure attempts use distinct URL-safe verifier and state values', () {
    final a = SpotifyAuthorizationAttempt.create();
    final b = SpotifyAuthorizationAttempt.create();
    expect(a.verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43,128}$')));
    expect(a.verifier, isNot(b.verifier));
    expect(a.state, isNot(b.state));
  });
  test(
      'code exchange sends the verifier without a client secret and retains expiry',
      () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://accounts.spotify.com/api/token');
      final body = Uri.splitQueryString(request.body);
      expect(body['grant_type'], 'authorization_code');
      expect(body['code_verifier'], 'v' * 43);
      expect(body['redirect_uri'], redirect.toString());
      expect(body.containsKey('client_secret'), isFalse);
      return http.Response(
          jsonEncode({
            'access_token': 'synthetic-token',
            'expires_in': 3600,
            'token_type': 'Bearer'
          }),
          200);
    });
    final now = DateTime.utc(2026, 11, 12);
    final token = await exchangeSpotifyCode(
        client: client,
        clientId: 'synthetic-client',
        redirect: redirect,
        code: 'fixture',
        verifier: 'v' * 43,
        now: now);
    expect(token.value, 'synthetic-token');
    expect(token.expiresAt, now.add(const Duration(hours: 1)));
    expect(token.isUsableAt(now.add(const Duration(minutes: 59))), isTrue);
    expect(token.isUsableAt(token.expiresAt), isFalse);
  });
  test('failed or malformed token exchanges do not create usable sessions',
      () async {
    for (final response in [
      http.Response('{}', 401),
      http.Response('{}', 200),
      http.Response(
          '{"access_token":"fixture","expires_in":-1,"token_type":"Bearer"}',
          200)
    ]) {
      await expectLater(
          exchangeSpotifyCode(
              client: MockClient((_) async => response),
              clientId: 'synthetic-client',
              redirect: redirect,
              code: 'fixture',
              verifier: 'v' * 43,
              now: DateTime.utc(2026)),
          throwsStateError);
    }
  });
}
