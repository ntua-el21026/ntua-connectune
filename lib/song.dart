import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:listen_around/notification.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vibration/vibration.dart';

class SongInteractionPage extends StatefulWidget {
  final String username;
  final String songTitle;
  final String imageUrl;
  final String fcmToken;
  final String userId;
  final String artistName;

  const SongInteractionPage({
    Key? key,
    required this.username,
    required this.songTitle,
    required this.imageUrl,
    required this.fcmToken,
    required this.userId,
    required this.artistName,
  }) : super(key: key);

  @override
  _SongInteractionPageState createState() => _SongInteractionPageState();
}

class _SongInteractionPageState extends State<SongInteractionPage> {
  double _rotation = 0.0;
  final double _rotationLimit = 60.0;
  final ImagePicker _picker = ImagePicker();
  File? _capturedImage;
  bool _hasLiked = false;
  bool _hasSuperLiked = false;
  bool _isRotating = false;

  void _handleRotation(double angle) {
    if (_hasLiked || _hasSuperLiked) return; // Prevent further actions if already liked

    setState(() {
      _isRotating = true;
      _rotation = max(-_rotationLimit, min(_rotationLimit, angle));
    });
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

  Future<String> _uploadImageToFirebase(File image) async {
    final storageRef = FirebaseStorage.instance.ref().child('super_likes/${DateTime.now().millisecondsSinceEpoch}.jpg');
    final uploadTask = storageRef.putFile(image);
    final snapshot = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();
    return downloadUrl;
  }

  void _handleRotationEnd(_) {
    if (!_isRotating) return;

    setState(() {
      _isRotating = false;

      // Only trigger actions if we reached the rotation limit
      if (_rotation >= _rotationLimit && !_hasSuperLiked) {
        _superLike();
        _hasSuperLiked = true;
      } else if (_rotation <= -_rotationLimit && !_hasLiked) {
        _like();
        _hasLiked = true;
      }

      _rotation = 0.0;
    });
  }

  void _like() async {
    print('Like registered for ${widget.username}');

    await FCMService.sendNotification(
      token: widget.fcmToken,
      title: 'You got a new Like!',
      body: 'Someone liked your song ${widget.songTitle}!',
      data: {
        'type': 'like',
        'songTitle': widget.songTitle,
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

  Future<void> _superLike() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        setState(() {
          _capturedImage = File(photo.path);
        });

        final imageUrl = await _uploadImageToFirebase(_capturedImage!);

        // Add the new superlike to the recipient's listening data
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

        // Send the notification
        await FCMService.sendNotification(
          token: widget.fcmToken,
          title: 'You got a Super Like!',
          body: 'Someone super liked your song ${widget.songTitle}!',
          data: {
            'type': 'superlike',
            'userId': FirebaseAuth.instance.currentUser!.uid, // Include sender ID
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Listening'),
      ),
      body: Center(
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
                      widget.imageUrl,
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
                      widget.username,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(0.0),
              child: Column(
                children: [
                  Text(
                    widget.songTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    widget.artistName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onPanUpdate: (details) => _handleRotation(_rotation + details.delta.dx),
                onPanEnd: _handleRotationEnd,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      bottom: -130,
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
      ),
    );
  }
}
