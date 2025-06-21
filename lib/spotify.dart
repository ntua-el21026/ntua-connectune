import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:listen_around/auth/login.dart';
import 'package:listen_around/home.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SpotifyAuthPage extends StatefulWidget {
  const SpotifyAuthPage({Key? key}) : super(key: key);

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
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  Future<void> _checkStoredToken() async {
    await _secureStorage.delete(key: _accessTokenKey);
    final token = await _secureStorage.read(key: _accessTokenKey);
    if (token != null) {
      setState(() {
        _accessToken = token;
      });
      _navigateToHomePage();
    }
  }

  Future<void> _authenticateSpotify() async {
    setState(() => _isLoading = true);

    try {
      const clientId = '';
      const redirectUri = '';
      const scope = 'user-read-playback-state user-read-currently-playing';

      final authUrl = Uri.parse('https://accounts.spotify.com/authorize'
          '?client_id=$clientId'
          '&response_type=token'
          '&redirect_uri=$redirectUri'
          '&scope=$scope');


      // Launch the authentication URL and get the callback URL
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: 'listen-around',
      );

      // Extract the token from the callback URL
      final fragment = Uri.parse(result).fragment;
      final params = Uri.splitQueryString(fragment);
      final token = params['access_token'];

      if (token != null) {
        await _secureStorage.write(key: _accessTokenKey, value: token);
        setState(() => _accessToken = token);
        _navigateToHomePage();
      } else {
        throw Exception('Access token not found');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Authentication failed: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToHomePage() {
    if (_accessToken != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
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
            : Column(mainAxisAlignment: MainAxisAlignment.center, 
            children: [
                ElevatedButton.icon(
                  onPressed: _authenticateSpotify,
                  icon: const Icon(Icons.music_note),
                  label: const Text('Connect with Spotify'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
