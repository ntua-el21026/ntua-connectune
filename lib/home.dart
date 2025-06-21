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
  bool _isSubscriptionActive = false;

  @override
  void initState() {
    super.initState();
    //_requestNotificationPermission();

    _setupLocationAndPermissions();
    _refreshTimer = Timer.periodic(const Duration(seconds: 180), (_) {
      _updateCurrentlyPlaying();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestNotificationPermission() async {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;

    final NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification permissions denied'),
        ),
      );
    } else if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification permissions granted'),
        ),
      );
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Provisional notification permissions granted'),
        ),
      );
    }
  }

  Future<void> _setupLocationAndPermissions() async {
    try {
      final locationPermission = await location.requestPermission();
      if (locationPermission == PermissionStatus.granted) {
        location.changeSettings(accuracy: LocationAccuracy.high, interval: 10000);
        await _getCurrentLocation();
        await _updateCurrentlyPlaying();
      } else {
        setState(() {
          isSpotifyPlaying = false;
        });
      }
    } catch (e) {
      debugPrint('Error setting up location: ${e.toString()}');
    }
  }

  Future<void> _getCurrentLocation() async {
    print('getting location');
    try {
      _currentLocation = await location.getLocation();
      print(_currentLocation);
    } catch (e) {
      debugPrint('Error getting location: ${e.toString()}');
    }
  }

  Future<void> _updateListeningData(Map<String, dynamic> trackData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _currentLocation != null) {
      String? fcmToken = await FirebaseMessaging.instance.getToken();

      // Fetch user data to include name and likes
      final userSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userSnapshot.data() ?? {};

      final name = userData['name'] ?? 'Unknown User';
      final likes = (userData['likes'] ?? 0);

      await FirebaseFirestore.instance.collection('listening_data').doc(user.uid).set({
        'userId': user.uid,
        'song': trackData['song'],
        'fcmToken': fcmToken,
        'songId': trackData['songId'],
        'artistName': trackData['artistName'],
        'previewUrl': trackData['previewUrl'],
        'name': name, // Add user's name
        'likes': likes, // Add user's likes
        'imageUrl': trackData['imageUrl'],
        'geo': GeoFirePoint(
          GeoPoint(
            _currentLocation!.latitude!,
            _currentLocation!.longitude!,
          ),
        ).data,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  void _startNearbyUsersSubscription() {
    if (_currentLocation == null) return;

    _isSubscriptionActive = true; // Mark the subscription as active
    final currentUser = FirebaseAuth.instance.currentUser;

    final geoCollection = GeoCollectionReference(FirebaseFirestore.instance.collection('listening_data'));
    _subscription = geoCollection
        .subscribeWithin(
      center: GeoFirePoint(
        GeoPoint(_currentLocation!.latitude!, _currentLocation!.longitude!),
      ),
      radiusInKm: 0.5,
      field: 'geo',
      geopointFrom: (data) {
        final geoPoint = (data['geo']['geopoint'] as GeoPoint);
        return GeoPoint(geoPoint.latitude, geoPoint.longitude);
      },
      strictMode: true,
    )
        .listen((List<DocumentSnapshot<Map<String, dynamic>>> results) {
      final now = DateTime.now();
      final users = results
          .map((doc) {
            final data = doc.data();
            if (data == null) return {};
            if (data['userId'] == currentUser?.uid) return null;
            final timestamp = data['timestamp'] as Timestamp?;
            if (timestamp == null || now.difference(timestamp.toDate()).inSeconds > 180) {
              return null; // Exclude data older than 180 seconds
            }

            final today = DateTime.now();
            final formattedDate = '${today.year}-${today.month}-${today.day}';


            // Valid data
            return {
              'userId': doc.id,
              'song': data['song'],
              'artistName': data['artistName'],
              'previewUrl': data['previewUrl'],
              'imageUrl': data['imageUrl'],
              'fcmToken': data['fcmToken'],
              'name': data['name'],
              'likes': data['likes']?[formattedDate] ?? 0 
            };
          })
          .where((user) => user != null)
          .toList(); // Remove nulls

      setState(() {
        nearbyUsers = users.cast<Map<String, dynamic>>();
      });
    });
  }

  Future<void> _updateCurrentlyPlaying() async {
    if (_currentLocation == null) return;

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/currently-playing'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      );

      print('Getting the current playing');
      print(response.statusCode);
      print(response.body);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = json.decode(response.body);
        final track = data['item'];
        final playing = data['is_playing'];

        if (track != null && playing == true) {
          print('setting true');
          setState(() {
            isSpotifyPlaying = true;
          });
          await _updateListeningData({
            'song': track['name'],
            'songId': track['id'],
            'artistName': track['artists'][0]['name'],
            'previewUrl': track['preview_url'],
            'imageUrl': track['album']['images'][0]['url'],
          });
          if (!_isSubscriptionActive) {
            print('starting the subscription');
            _startNearbyUsersSubscription();
          }
        } else {
          print('setting false');
          setState(() {
            isSpotifyPlaying = false;
          });
          if (_isSubscriptionActive) {
            _subscription?.cancel();
            _isSubscriptionActive = false;
          }
        }
      } else {
        print('setting false');
        setState(() {
          isSpotifyPlaying = false;
        });
      }
    } catch (e) {
      setState(() {
        isSpotifyPlaying = false;
      });
      debugPrint('Error updating current track: ${e.toString()}');
    }
  }

  void navigateToSuperLikePage(BuildContext context, Map<String, dynamic> superLikeData) async {
    // Navigate to a page displaying the super like
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SuperLikePage(superLikeData: superLikeData),
      ),
    );

    // Delete the super like record and the image after viewing
    await FirebaseFirestore.instance.collection('super_likes').doc(superLikeData['id']).delete();

    // Refresh the listener
    setState(() {});
  }

  void navigateToSongInteractionPage(BuildContext context, String username, String songTitle, String imageUrl, String fcmToken, String userId, String artistName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SongInteractionPage(username: username, songTitle: songTitle, imageUrl: imageUrl, fcmToken: fcmToken, userId: userId, artistName: artistName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget noSpotifyWidget = const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 50, color: Colors.grey),
          SizedBox(height: 10),
          Text(
            'Please play a song on Spotify to see nearby listeners',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
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
              await _getCurrentLocation();
              await _updateCurrentlyPlaying();
              setState(() => isLoading = false);
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
                  stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final userData = snapshot.data!.data() as Map<String, dynamic>?;
                      final today = DateTime.now();
                      final formattedDate = '${today.year}-${today.month}-${today.day}';
                      final likes = userData?['likes']?[formattedDate] ?? 0;

                      return GestureDetector(
                        onTap: () {
                          // Handle likes container tap
                        },
                        child: Stack(
                          clipBehavior: Clip.none, // Allows positioning outside the widget bounds
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
                                backgroundColor: const Color.fromARGB(255, 81, 64, 124),
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
                      return const Center(child: Text('No likes data available'));
                    }
                  },
                ),
                // User Info container
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final userData = snapshot.data!.data() as Map<String, dynamic>?;
                      final username = userData?['name'] ?? 'User';

                      return GestureDetector(
                        onTap: () {
                          // Navigate to profile page
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfilePage(),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Text(
                                username,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.person, size: 32, color: Colors.black),
                            ],
                          ),
                        ),
                      );
                    } else {
                      return const Center(child: Text('No user data available'));
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
                              // Sort the users by likes (most likes on top)
                              nearbyUsers.sort((a, b) {
                                final likesA = a['likes'] ?? 0;
                                final likesB = b['likes'] ?? 0;
                                return likesB.compareTo(likesA); // Descending order
                              });

                              final user = nearbyUsers[index];
                             
                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: GestureDetector(
                                  onTap: () => navigateToSongInteractionPage(
                                      context, user['name'], user['song'], user['imageUrl'], user['fcmToken'], user['userId'], user['artistName']),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16.0),
                                    decoration: BoxDecoration(
                                      color: const Color.fromARGB(255, 81, 64, 124), // Purple container background
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 3,
                                          offset: const Offset(0, 5), // Shadow position
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
                                          child: user['imageUrl'] != null
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
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  user['song'] ?? 'Unknown Song',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  user['artistName'] ?? 'Unknown Artist',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white70,
                                                  ),
                                                  maxLines: 2, // Limit to 2 lines
                                                  overflow: TextOverflow.ellipsis, //
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Likes count
                                        Padding(
                                          padding: const EdgeInsets.only(right: 16.0),
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
