import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:listen_around/auth/login.dart';
import 'package:listen_around/home.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'spotify_oauth.dart';

class SpotifyAuthPage extends StatefulWidget {
  final bool forceReconnect;
  const SpotifyAuthPage({Key? key, this.forceReconnect = false})
      : super(key: key);

  @override
  _SpotifyAuthPageState createState() => _SpotifyAuthPageState();
}

class _SpotifyAuthPageState extends State<SpotifyAuthPage> {
  static const String _accessTokenKey = 'spotify_access_token';
  final _secureStorage = const FlutterSecureStorage();
  String? _accessToken;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkStoredToken();
  }

  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  Future<void> _checkStoredToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key = '$_accessTokenKey:$uid';
    final expiryKey = 'spotify_expires_at:$uid';
    try {
      if (widget.forceReconnect) {
        await _secureStorage.delete(key: key);
        await _secureStorage.delete(key: expiryKey);
        return;
      }
      final token = await _secureStorage.read(key: key);
      final expiry =
          DateTime.tryParse(await _secureStorage.read(key: expiryKey) ?? '');
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      if (token != null &&
          expiry != null &&
          SpotifyAccessToken(token, expiry).isUsableAt(DateTime.now())) {
        _accessToken = token;
        _navigateToHomePage();
      }
    } catch (_) {
      // A locked/unavailable keystore must not prevent a fresh authorization.
    }
  }

  Future<void> _authenticateSpotify() async {
    setState(() => _isLoading = true);
    try {
      const clientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
      const redirectValue = String.fromEnvironment('SPOTIFY_REDIRECT_URI');
      final redirect = Uri.tryParse(redirectValue);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null ||
          clientId.isEmpty ||
          redirect == null ||
          !redirect.hasScheme) {
        throw StateError(
            'Configure the Spotify client ID and registered redirect URI');
      }
      final attempt = SpotifyAuthorizationAttempt.create();
      final result = await FlutterWebAuth2.authenticate(
        url: attempt
            .authorizationUri(clientId: clientId, redirect: redirect)
            .toString(),
        callbackUrlScheme: redirect.scheme,
      );
      final code = attempt.readCode(result, redirect);
      final client = http.Client();
      late SpotifyAccessToken token;
      try {
        token = await exchangeSpotifyCode(
            client: client,
            clientId: clientId,
            redirect: redirect,
            code: code,
            verifier: attempt.verifier,
            now: DateTime.now());
      } finally {
        client.close();
      }
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      await _secureStorage.write(
          key: '$_accessTokenKey:$uid', value: token.value);
      await _secureStorage.write(
          key: 'spotify_expires_at:$uid',
          value: token.expiresAt.toIso8601String());
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      _accessToken = token.value;
      _navigateToHomePage();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Spotify connection was not completed. Check configuration and try again.')),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToHomePage() {
    if (_accessToken != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/home'),
          builder: (context) => HomePage(accessToken: _accessToken!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Spotify'),
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                ElevatedButton.icon(
                  onPressed: _authenticateSpotify,
                  icon: const Icon(Icons.music_note),
                  label: const Text('Connect with Spotify'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _logout(context),
                  child: const Text('Logout'),
                ),
              ]),
      ),
    );
  }
}
