import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:location/location.dart';
import 'dart:async';
import 'package:listen_around/super_like_image.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:listen_around/song.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:listen_around/profile_page.dart';
import 'package:listen_around/discovery_data.dart';
import 'package:listen_around/spotify.dart';

class HomePage extends StatefulWidget {
  final String accessToken;

  const HomePage({Key? key, required this.accessToken}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Location location = Location();
  LocationData? _currentLocation;
  List<Map<String, dynamic>> nearbyUsers = [];
  bool isLoading = false;
  bool isSpotifyPlaying = false;
  StreamSubscription? _subscription;
  Timer? _refreshTimer;
  int _subscriptionVersion = 0;
  Future<void>? _refreshFuture;
  bool _profileOpen = false;
  bool _spotifySessionExpired = false;

  @override
  void initState() {
    super.initState();
    _setupLocationAndPermissions();
    _refreshTimer = Timer.periodic(const Duration(seconds: 180), (_) {
      _refreshListening();
    });
  }

  @override
  void dispose() {
    _subscriptionVersion++;
    _subscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _stopNearbyUsersSubscription() {
    _subscriptionVersion++;
    _subscription?.cancel();
    _subscription = null;
    if (mounted) {
      setState(() => nearbyUsers = []);
    }
  }

  void _stopListening() {
    _stopNearbyUsersSubscription();
    if (mounted) {
      setState(() => isSpotifyPlaying = false);
    }
  }

  Future<void> _setupLocationAndPermissions() async {
    try {
      var serviceEnabled = await location.serviceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!mounted) return;
      }
      if (!serviceEnabled) {
        _stopListening();
        return;
      }
      final locationPermission = await location.requestPermission();
      if (!mounted) return;
      if (locationPermission == PermissionStatus.granted) {
        await location.changeSettings(
          accuracy: LocationAccuracy.high,
          interval: 10000,
        );
        if (!mounted) return;
        await _refreshListening();
      } else {
        _stopListening();
      }
    } catch (e) {
      _stopListening();
      debugPrint('Error setting up location: $e');
    }
  }

  Future<bool> _getCurrentLocation() async {
    try {
      final currentLocation = await location.getLocation();
      if (!mounted) return false;
      if (currentLocation.latitude == null ||
          currentLocation.longitude == null) {
        _currentLocation = null;
        return false;
      }
      _currentLocation = currentLocation;
      return true;
    } catch (e) {
      _currentLocation = null;
      debugPrint('Error getting location: $e');
      return false;
    }
  }

  Future<void> _refreshListening() async {
    if (_refreshFuture != null) return _refreshFuture!;
    if (!mounted ||
        _profileOpen ||
        _spotifySessionExpired ||
        FirebaseAuth.instance.currentUser == null) {
      return;
    }
    final refresh = _refreshListeningOnce();
    _refreshFuture = refresh;
    try {
      await refresh;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<void> _refreshListeningOnce() async {
    if (!await _getCurrentLocation()) {
      _stopListening();
      return;
    }
    if (!mounted || _profileOpen) return;
    // Each location refresh replaces the query's fixed geographic center.
    _stopNearbyUsersSubscription();
    await _updateCurrentlyPlaying();
  }

  Future<bool> _updateListeningData(Map<String, dynamic> trackData) async {
    final user = FirebaseAuth.instance.currentUser;
    final currentLocation = _currentLocation;
    if (user == null || currentLocation == null) return false;

    String fcmToken = '';
    try {
      fcmToken = await FirebaseMessaging.instance
              .getToken()
              .timeout(const Duration(seconds: 3)) ??
          '';
    } catch (e) {
      // Messaging availability must not prevent nearby-listener discovery.
      debugPrint('Messaging token unavailable: $e');
    }
    if (!mounted ||
        _profileOpen ||
        FirebaseAuth.instance.currentUser?.uid != user.uid) {
      return false;
    }

    final userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!mounted ||
        _profileOpen ||
        FirebaseAuth.instance.currentUser?.uid != user.uid) {
      return false;
    }
    final userData = userSnapshot.data() ?? {};
    await FirebaseFirestore.instance
        .collection('listening_data')
        .doc(user.uid)
        .set({
      'userId': user.uid,
      'song': trackData['song'],
      'fcmToken': fcmToken,
      'songId': trackData['songId'],
      'artistName': trackData['artistName'],
      'previewUrl': trackData['previewUrl'],
      'name': userData['name'] ?? 'Unknown User',
      'likes': normalizedDailyLikes(userData['likes']),
      'imageUrl': trackData['imageUrl'],
      'geo': GeoFirePoint(
        GeoPoint(currentLocation.latitude!, currentLocation.longitude!),
      ).data,
      'timestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return mounted &&
        !_profileOpen &&
        FirebaseAuth.instance.currentUser?.uid == user.uid;
  }

  void _startNearbyUsersSubscription() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (!mounted ||
        _profileOpen ||
        _currentLocation == null ||
        currentUser == null) {
      return;
    }
    final version = _subscriptionVersion;
    final geoCollection = GeoCollectionReference(
      FirebaseFirestore.instance.collection('listening_data'),
    );
    _subscription = geoCollection
        .subscribeWithin(
      center: GeoFirePoint(
        GeoPoint(_currentLocation!.latitude!, _currentLocation!.longitude!),
      ),
      radiusInKm: 0.5,
      field: 'geo',
      geopointFrom: (data) => data['geo']['geopoint'] as GeoPoint,
      strictMode: true,
    )
        .listen((List<DocumentSnapshot<Map<String, dynamic>>> results) {
      if (!mounted ||
          version != _subscriptionVersion ||
          FirebaseAuth.instance.currentUser?.uid != currentUser.uid) {
        return;
      }
      final now = DateTime.now();
      final users = results
          .map((doc) {
            final data = doc.data();
            final timestamp = data?['timestamp'];
            return discoveryListener(
              userId: doc.id,
              data: data,
              currentUserId: currentUser.uid,
              now: now,
              updatedAt: timestamp is Timestamp ? timestamp.toDate() : null,
            );
          })
          .whereType<Map<String, dynamic>>()
          .toList();
      users.sort((a, b) => (b['likes'] as num).compareTo(a['likes'] as num));
      setState(() => nearbyUsers = users);
    }, onError: (Object error) {
      if (!mounted || version != _subscriptionVersion) return;
      _stopNearbyUsersSubscription();
      debugPrint('Error discovering nearby listeners: $error');
    });
  }

  Future<void> _updateCurrentlyPlaying() async {
    if (!mounted ||
        _profileOpen ||
        _currentLocation == null ||
        FirebaseAuth.instance.currentUser == null) {
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/currently-playing'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 20));
      if (!mounted ||
          _profileOpen ||
          FirebaseAuth.instance.currentUser == null) {
        return;
      }
      if (response.statusCode == 401) {
        _spotifySessionExpired = true;
        _refreshTimer?.cancel();
        _stopListening();
        return;
      }
      if (response.statusCode != 200 || response.body.isEmpty) {
        _stopListening();
        return;
      }
      final data = json.decode(response.body);
      final track = data['item'];
      if (track == null || data['is_playing'] != true) {
        _stopListening();
        return;
      }
      final published = await _updateListeningData({
        'song': track['name'],
        'songId': track['id'],
        'artistName': track['artists'][0]['name'],
        'previewUrl': track['preview_url'],
        'imageUrl': (track['album']['images'] as List).isEmpty
            ? ''
            : track['album']['images'][0]['url'],
      });
      if (!published || !mounted || _profileOpen) return;
      setState(() => isSpotifyPlaying = true);
      _startNearbyUsersSubscription();
    } catch (e) {
      _stopListening();
      debugPrint('Error updating current track: $e');
    }
  }

  void _reconnectSpotify() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => const SpotifyAuthPage(forceReconnect: true)),
      (_) => false,
    );
  }

  Future<void> _openProfile() async {
    if (_profileOpen) return;
    _profileOpen = true;
    _stopNearbyUsersSubscription();
    // Let an already dispatched publication settle without making Profile
    // inaccessible offline. The profile guard prevents any new publication.
    await _refreshFuture?.timeout(const Duration(seconds: 3), onTimeout: () {});
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
    _profileOpen = false;
    if (mounted) await _refreshListening();
  }

  void navigateToSuperLikePage(
      BuildContext context, Map<String, dynamic> superLikeData) async {
    // Navigate to a page displaying the super like
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SuperLikePage(superLikeData: superLikeData),
      ),
    );

    // Delete the super like record and the image after viewing
    await FirebaseFirestore.instance
        .collection('super_likes')
        .doc(superLikeData['id'])
        .delete();

    // Refresh the listener
    if (mounted) setState(() {});
  }

  void navigateToSongInteractionPage(
      BuildContext context,
      String username,
      String songTitle,
      String imageUrl,
      String fcmToken,
      String userId,
      String artistName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SongInteractionPage(
            username: username,
            songTitle: songTitle,
            imageUrl: imageUrl,
            fcmToken: fcmToken,
            userId: userId,
            artistName: artistName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    Widget noSpotifyWidget = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.music_off, size: 50, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            _spotifySessionExpired
                ? 'Reconnect to Spotify to see nearby listeners'
                : 'Please play a song on Spotify to see nearby listeners',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          if (_spotifySessionExpired)
            TextButton(
                onPressed: _reconnectSpotify,
                child: const Text('Reconnect to Spotify')),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              setState(() => isLoading = true);
              await _refreshListening();
              if (mounted) setState(() => isLoading = false);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Likes and Super Likes containers
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Likes container
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUserId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final userData =
                          snapshot.data!.data() as Map<String, dynamic>?;
                      final today = DateTime.now();
                      final formattedDate =
                          '${today.year}-${today.month}-${today.day}';
                      final likes =
                          dailyLikeCount(userData?['likes'], formattedDate);

                      return GestureDetector(
                        onTap: () {
                          // Handle likes container tap
                        },
                        child: Stack(
                          clipBehavior: Clip
                              .none, // Allows positioning outside the widget bounds
                          children: [
                            // Background container
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Image.asset(
                                'assets/images/music.png', // Replace with your asset image path
                                width: 25,
                                height: 25,
                              ),
                            ),
                            // Circle with number of likes
                            Positioned(
                              top: -10,
                              right: -10,
                              child: CircleAvatar(
                                backgroundColor:
                                    const Color.fromARGB(255, 81, 64, 124),
                                radius: 16,
                                child: Text(
                                  '$likes',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      return const Center(
                          child: Text('No likes data available'));
                    }
                  },
                ),
                // User Info container
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUserId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final userData =
                          snapshot.data!.data() as Map<String, dynamic>?;
                      final username = userData?['name'] ?? 'User';

                      return GestureDetector(
                        onTap: _openProfile,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Text(
                                username,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.person,
                                  size: 32, color: Colors.black),
                            ],
                          ),
                        ),
                      );
                    } else {
                      return const Center(
                          child: Text('No user data available'));
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : !isSpotifyPlaying
                    ? noSpotifyWidget
                    : nearbyUsers.isEmpty
                        ? const Center(child: Text('No nearby listeners found'))
                        : ListView.builder(
                            itemCount: nearbyUsers.length,
                            itemBuilder: (context, index) {
                              final user = nearbyUsers[index];

                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: GestureDetector(
                                  onTap: () => navigateToSongInteractionPage(
                                      context,
                                      user['name'],
                                      user['song'],
                                      user['imageUrl'],
                                      user['fcmToken'],
                                      user['userId'],
                                      user['artistName']),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16.0),
                                    decoration: BoxDecoration(
                                      color: const Color.fromARGB(255, 81, 64,
                                          124), // Purple container background
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 3,
                                          offset: const Offset(
                                              0, 5), // Shadow position
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        // Album cover or default icon
                                        ClipRRect(
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(20),
                                            bottomLeft: Radius.circular(20),
                                          ),
                                          child: (user['imageUrl'] as String)
                                                  .isNotEmpty
                                              ? Image.network(
                                                  user['imageUrl'],
                                                  width: 100,
                                                  height: 100,
                                                  fit: BoxFit.cover,
                                                )
                                              : Container(
                                                  width: 100,
                                                  height: 100,
                                                  color: Colors.grey.shade300,
                                                  child: const Icon(
                                                    Icons.music_note,
                                                    size: 40,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                        ),
                                        // Song and user information
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  user['song'] ??
                                                      'Unknown Song',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  user['artistName'] ??
                                                      'Unknown Artist',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white70,
                                                  ),
                                                  maxLines:
                                                      2, // Limit to 2 lines
                                                  overflow:
                                                      TextOverflow.ellipsis, //
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Likes count
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              right: 16.0),
                                          child: CircleAvatar(
                                            backgroundColor: Colors.black,
                                            radius: 16,
                                            child: Text(
                                              '${user['likes'] ?? 0}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          )
        ],
      ),
    );
  }
}
