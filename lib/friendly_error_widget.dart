import 'package:flutter/material.dart';

class FriendlyErrorWidget extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const FriendlyErrorWidget({
    super.key,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // A friendly placeholder icon! (You can replace this with an Image.asset of a dog or a broken piggy bank later)
            // The New "Amazon Style" Real Dog Image
            ClipRRect(
              borderRadius: BorderRadius.circular(100), // Makes it a perfect circle
              child: Image.network(
                // A very cute, apologetic-looking dog from Unsplash
                'https://images.unsplash.com/photo-1543466835-00a7907e9de1?q=80&w=200&auto=format&fit=crop',
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                // If the internet is so broken that even the dog won't load, fallback to the icon!
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.pets_rounded,
                  size: 80,
                  color: Colors.teal.shade200,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Ruh-roh! Something went wrong.',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // We use a helper function to translate scary robot errors into human words
            Text(
              _getFriendlyMessage(errorMessage),
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1CC29F), // Chanda Teal
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  // This translates raw Firebase errors into user-friendly text
  String _getFriendlyMessage(String rawError) {
    if (rawError.contains('permission-denied')) {
      return "We couldn't access your data. Make sure you are logged in correctly.";
    } else if (rawError.contains('network') || rawError.contains('unavailable')) {
      return "Looks like your internet connection is taking a nap.";
    }
    // Fallback if we don't recognize the error, just show it but keep it small
    return "We hit a little snag:\n$rawError";
  }
}