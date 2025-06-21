import 'package:flutter/material.dart';

class SuperLikePage extends StatelessWidget {
  final Map<String, dynamic> superLikeData;

  const SuperLikePage({Key? key, required this.superLikeData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final String senderName = superLikeData['fromName'] ?? 'Unknown User';
    final String imageUrl = superLikeData['imageUrl'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Like'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Display the sender's name
            const SizedBox(height: 20),

            // Display the image
            imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    height: 300,
                    width: 300,
                    fit: BoxFit.cover,
                  )
                : const Icon(
                    Icons.image_not_supported,
                    size: 100,
                    color: Colors.grey,
                  ),
            const SizedBox(height: 20),

            // "Back to Home" button
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Go back to the home page
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'Back to Home',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
