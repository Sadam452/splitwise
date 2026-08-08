import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditSplitScreen extends StatefulWidget {
  final String groupId;
  final String orderId;
  final Map<String, dynamic> orderData; 
  final List<String> allMemberIds;
  final Map<String, dynamic> membersData;

  const EditSplitScreen({
    super.key,
    required this.groupId,
    required this.orderId,
    required this.orderData,
    required this.allMemberIds,
    required this.membersData,
  });

  @override
  State<EditSplitScreen> createState() => _EditSplitScreenState();
}

class _EditSplitScreenState extends State<EditSplitScreen> {
  late String _currentUserUid;
  
  // Tracks which items are currently saving so we can show a loading spinner
  // and prevent spam-clicking.
  final Set<int> _processingItems = {}; 
  int _changesMade = 0;
  String _getUserName(String uid) {
    final userData = widget.membersData[uid];
    if (userData == null) return 'Unknown';
    if (userData['firstName'] != null && userData['firstName'].toString().isNotEmpty) {
      return userData['firstName'];
    }
    final email = userData['email']?.toString() ?? 'User';
    return email.split('@').first;
  }

  @override
  void initState() {
    super.initState();
    _currentUserUid = FirebaseAuth.instance.currentUser!.uid;
  }

  // Runs instantly when a checkbox is tapped
  Future<void> _toggleItemSplit(int itemIndex, bool wantsToParticipate) async {
    setState(() => _processingItems.add(itemIndex));
    // INCREMENT THE COUNTER WHEN THEY CLICK A CHECKBOX
    _changesMade++;

    final docRef = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('orders')
        .doc(widget.orderId);

    try {
      // Return a String from the transaction to avoid throwing errors and crashing the stream
      final result = await FirebaseFirestore.instance.runTransaction<String>((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return "ORDER_NOT_FOUND";

        final data = snapshot.data()!;
        List<dynamic> dbItems = data['items'] ?? [];

        if (itemIndex >= dbItems.length) return "ITEM_NOT_FOUND";

        // Read the live data for this specific item
        Map<String, dynamic> dbItem = Map<String, dynamic>.from(dbItems[itemIndex]);
        List<String> dbSplitBetween = List<String>.from(dbItem['splitBetween'] ?? widget.allMemberIds);

        if (wantsToParticipate) {
          // Add user safely
          if (!dbSplitBetween.contains(_currentUserUid)) {
            dbSplitBetween.add(_currentUserUid);
          }
        } else {
          // Remove user safely
          if (dbSplitBetween.contains(_currentUserUid)) {
            // BACKEND CHECK: Look at the live data.
            // If they are the last person, abort gracefully by returning a string.
            if (dbSplitBetween.length <= 1) {
              return "MIN_ONE_USER"; 
            }
            dbSplitBetween.remove(_currentUserUid);
          }
        }

        // Apply changes
        dbItem['splitBetween'] = dbSplitBetween;
        dbItems[itemIndex] = dbItem;

        // Push updates to Firestore
        transaction.update(docRef, {
          'items': dbItems,
          'updatedBy': _currentUserUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        return "SUCCESS";
      });

      // Handle the UI based on the transaction result
      if (mounted) {
        if (result == "MIN_ONE_USER") {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Someone must pay for this item! You cannot remove yourself.')),
          );
        } else if (result != "SUCCESS") {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update: $result')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingItems.remove(itemIndex));
      }
    }
  }

  void _logSummaryActivity() {
    if (_changesMade > 0) {
      final userName = widget.membersData[_currentUserUid]?['firstName'] ?? 'Someone';
      
      FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc(widget.orderId)
          .collection('activities')
          .add({
        'type': 'system',
        'text': '$userName updated their split details.',
        'userId': _currentUserUid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
   return PopScope(
    canPop: true,
    onPopInvoked: (didPop) {
      if(didPop){
        _logSummaryActivity();
      }
    },
    child: Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Edit My Split', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      // StreamBuilder keeps the list updated in real-time
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('orders')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.deepPurple));
          }

          final data = snapshot.data?.data() as Map<String, dynamic>?;
          if (data == null) return const Center(child: Text('Bill not found'));

          final items = data['items'] as List<dynamic>? ?? [];

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 40, top: 16, left: 16, right: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index] as Map<String, dynamic>;
              final List<String> splitBetween = List<String>.from(item['splitBetween'] ?? widget.allMemberIds);
              final splitNames = splitBetween.map((uid) => _getUserName(uid)).join(', ');
              final isParticipating = splitBetween.contains(_currentUserUid);
              final isProcessing = _processingItems.contains(index);

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: CheckboxListTile(
                  activeColor: Colors.deepPurple,
                  title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                  isThreeLine: true,
                  subtitle: Text('₹${item['price']}\nSplit among: $splitNames',),
                  value: isParticipating,
                  // Toggles the specific item directly when clicked
                  onChanged: isProcessing ? null : (bool? checked) {
                    if (checked != null) {
                      _toggleItemSplit(index, checked);
                    }
                  },
                  secondary: isProcessing 
                      ? const SizedBox(
                          width: 20, 
                          height: 20, 
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple)
                        ) 
                      : null,
                ),
              );
            },
          );
        },
      ),
    )
    );
  }
}