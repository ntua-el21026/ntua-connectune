import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:listen_around/notification.dart';
import 'package:listen_around/super_like_image.dart';
import 'package:vibration/vibration.dart';

class SuperLikeInteractionPage extends StatefulWidget {
  final String userId;
  final String superLikeSenderId; // The user ID of the person who sent the superlike

  const SuperLikeInteractionPage({
    Key? key,
    required this.userId,
    required this.superLikeSenderId,
  }) : super(key: key);

  @override
  _SuperLikeInteractionPageState createState() => _SuperLikeInteractionPageState();
}

class _SuperLikeInteractionPageState extends State<SuperLikeInteractionPage> {
  double _rotation = 0.0;
  final double _rotationLimit = 60.0;
  final ImagePicker _picker = ImagePicker();
  File? _capturedImage;
  bool _hasLiked = false;
  bool _hasSuperLiked = false;
  bool _isRotating = false;

  late Future<Map<String, dynamic>?> _listeningDataFuture;

  @override
  void initState() {
    super.initState();
    _listeningDataFuture = _fetchListeningData();
  }

  void _vibrate() {
    Vibration.vibrate();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2), // Duration the message is displayed
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchListeningData() async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    // Fetch the listening data of the user who sent the superlike
    final senderSnapshot = await FirebaseFirestore.instance.collection('listening_data').doc(widget.userId).get();

    // Fetch the listening data of the current user
    final currentUserSnapshot = await FirebaseFirestore.instance.collection('listening_data').doc(currentUserId).get();

    if (senderSnapshot.exists && currentUserSnapshot.exists) {
      return {
        'senderData': senderSnapshot.data(), // Data for the user who sent the superlike
        'currentUserData': currentUserSnapshot.data(), // Data for the current user
      };
    }
    return null;
  }

  void _handleRotation(double angle) {
    if (_hasLiked || _hasSuperLiked) return;

    setState(() {
      _isRotating = true;
      _rotation = max(-_rotationLimit, min(_rotationLimit, angle));
    });
  }

  void _handleRotationEnd(DragEndDetails details, String username, String fcmToken, String songTitle) {
    if (!_isRotating) return;

    setState(() {
      _isRotating = false;

      if (_rotation >= _rotationLimit && !_hasSuperLiked) {
        _superLike(songTitle, fcmToken);
        _hasSuperLiked = true;
      } else if (_rotation <= -_rotationLimit && !_hasLiked) {
        _like(username, fcmToken, songTitle);
        _hasLiked = true;
      }

      _rotation = 0.0;
    });
  }

  void _like(String username, String fcmToken, String songTitle) async {
    print('Like registered for $username');

    await FCMService.sendNotification(
      token: fcmToken,
      title: 'You got a new Like!',
      body: 'Someone liked your song $songTitle!',
      data: {
        'type': 'like',
        'songTitle': songTitle,
      },
    );

    final today = DateTime.now();
    final formattedDate = '${today.year}-${today.month}-${today.day}';

    await FirebaseFirestore.instance.collection('users').doc(widget.userId).set({
      'likes': {
        formattedDate: FieldValue.increment(1),
      }
    }, SetOptions(merge: true));

    _vibrate();

    // Show the SnackBar
    _showSnackBar('Like sent!');
  }

  Future<void> _superLike(String songTitle, String fcmToken) async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        setState(() {
          _capturedImage = File(photo.path);
        });

        final imageUrl = await _uploadImageToFirebase(_capturedImage!);

        await FirebaseFirestore.instance.collection('listening_data').doc(widget.userId).update({
          'superlikes': FieldValue.arrayUnion([
            {
              'from': FirebaseAuth.instance.currentUser!.uid,
              'fromName': FirebaseAuth.instance.currentUser!.displayName,
              'imageUrl': imageUrl,
            }
          ]),
        });

        final today = DateTime.now();
        final formattedDate = '${today.year}-${today.month}-${today.day}';

        await FirebaseFirestore.instance.collection('users').doc(widget.userId).set({
          'likes': {
            formattedDate: FieldValue.increment(1),
          }
        }, SetOptions(merge: true));

        await FCMService.sendNotification(
          token: fcmToken,
          title: 'You got a Super Like!',
          body: 'Someone super liked your song $songTitle!',
          data: {
            'type': 'superlike',
            'userId': FirebaseAuth.instance.currentUser!.uid,
          },
        );
        _vibrate();

        // Show the SnackBar
        _showSnackBar('Super Like sent!');
      } else {
        setState(() {
          _hasSuperLiked = false;
        });
      }
    } catch (e) {
      debugPrint('Error sending superlike: $e');
    }
  }

  Future<String> _uploadImageToFirebase(File image) async {
    final storageRef = FirebaseStorage.instance.ref().child('super_likes/${DateTime.now().millisecondsSinceEpoch}.jpg');
    final uploadTask = storageRef.putFile(image);
    final snapshot = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();
    return downloadUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Like Interaction'),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _listeningDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('No listening data available.'));
          }

          final data = snapshot.data!;
          final senderData = data['senderData'] ?? {}; // Listening data of the user who sent the superlike
          final currentUserData = data['currentUserData'] ?? {}; // Listening data of the current user

          // Extract details for the sender's listening data
          final songTitle = senderData['song'] ?? 'Unknown Song';
          final imageUrl = senderData['imageUrl'] ?? '';
          final username = senderData['name'] ?? 'Unknown User';
          final fcmToken = senderData['fcmToken'] ?? '';
          final artistName = senderData['artistName'] ?? '';

          // Extract the superlikes from the current user's listening data
          final superlikes = (currentUserData['superlikes'] ?? []) as List<dynamic>;
          final matchingSuperlike = superlikes.firstWhere(
            (superlike) => superlike['from'] == widget.userId,
            orElse: () => null,
          );

          return Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    Container(
                      margin: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            offset: Offset(0, 4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Color.fromARGB(255, 115, 88, 182),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          username,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                    if (matchingSuperlike != null)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SuperLikePage(
                                  superLikeData: matchingSuperlike,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Color.fromARGB(255, 115, 88, 182),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.image,
                              size: 40,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      )
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(0.0),
                  child: Text(
                    songTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    artistName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onPanUpdate: (details) => _handleRotation(_rotation + details.delta.dx),
                    onPanEnd: (details) => _handleRotationEnd(details, username, fcmToken, songTitle),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          bottom: -100,
                          child: Transform.rotate(
                            angle: _rotation * pi / 180,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/vinyl.png',
                                  height: 360,
                                  width: 360,
                                ),
                                if (_capturedImage != null)
                                  Positioned(
                                    bottom: 10,
                                    child: Image.file(
                                      _capturedImage!,
                                      height: 50,
                                      width: 50,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
