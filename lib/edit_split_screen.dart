import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditSplitScreen extends StatefulWidget {
  final String groupId;
  final String orderId;
  final Map<String, dynamic> orderData;
  final List<String> allMemberIds;

  const EditSplitScreen({
    super.key,
    required this.groupId,
    required this.orderId,
    required this.orderData,
    required this.allMemberIds,
  });

  @override
  State<EditSplitScreen> createState() => _EditSplitScreenState();
}

class _EditSplitScreenState extends State<EditSplitScreen> {
  late List<Map<String, dynamic>> _items;
  late String _currentUserUid;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    
    // Create a deep copy of items so we can safely edit them locally
    _items = List<Map<String, dynamic>>.from(
      (widget.orderData['items'] as List<dynamic>? ?? []).map((item) => Map<String, dynamic>.from(item))
    );

    // Ensure every item has a 'splitBetween' array.
    for (var item in _items) {
      if (!item.containsKey('splitBetween')) {
        item['splitBetween'] = List<String>.from(widget.allMemberIds);
      } else {
        item['splitBetween'] = List<String>.from(item['splitBetween']);
      }
    }
  }

  Future<void> _updateSplit() async {
    setState(() => _isSaving = true);
    try {
      final docRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc(widget.orderId);

      // 1. Run a background transaction to safely merge data
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) throw Exception("Transaction not found.");

        final data = snapshot.data()!;
        List<dynamic> dbItems = data['items'] ?? [];
        List<Map<String, dynamic>> updatedItems = [];

        // 2. Loop through the live items from the database
        for (int i = 0; i < dbItems.length; i++) {
          Map<String, dynamic> dbItem = Map<String, dynamic>.from(dbItems[i]);
          List<String> dbSplitBetween = List<String>.from(dbItem['splitBetween'] ?? widget.allMemberIds);

          // Ensure we don't go out of bounds if items were edited
          if (i < _items.length) {
            bool wantsToParticipate = _items[i]['splitBetween'].contains(_currentUserUid);
            
            if (wantsToParticipate) {
              // Add user if they checked the box
              if (!dbSplitBetween.contains(_currentUserUid)) {
                dbSplitBetween.add(_currentUserUid);
              }
            } else {
              // Remove user if they unchecked the box
              if (dbSplitBetween.contains(_currentUserUid)) {
                if (dbSplitBetween.length <= 1) {
                  // ATOMIC CHECK: Abort if they are the last person
                  throw Exception("Cannot remove yourself from '${dbItem['name']}'. At least one person must split an item.");
                }
                dbSplitBetween.remove(_currentUserUid);
              }
            }
          }
          dbItem['splitBetween'] = dbSplitBetween;
          updatedItems.add(dbItem);
        }

        // 3. Save the safely merged items back to Firestore
        transaction.update(docRef, {
          'items': updatedItems,
          'updatedBy': _currentUserUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        // Strip out the "Exception: " text for a cleaner UI popup
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Edit My Split', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.only(bottom: 80, top: 16, left: 16, right: 16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = _items[index];
          final List<String> splitBetween = item['splitBetween'];
          final isParticipating = splitBetween.contains(_currentUserUid);

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: CheckboxListTile(
              activeColor: Colors.deepPurple,
              title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text('₹${item['price']} (Split among ${splitBetween.length})'),
              value: isParticipating,
              onChanged: (bool? checked) {
                setState(() {
                  if (checked == true) {
                    if (!splitBetween.contains(_currentUserUid)) splitBetween.add(_currentUserUid);
                  } else {
                    // Fast-fail UI validation (the transaction will also double-check this on the backend)
                    if (splitBetween.length > 1) {
                      splitBetween.remove(_currentUserUid);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Someone must pay for this item!')),
                      );
                    }
                  }
                  _items[index]['splitBetween'] = splitBetween;
                });
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        onPressed: _isSaving ? null : _updateSplit,
        icon: _isSaving 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.check),
        label: Text(_isSaving ? 'Updating...' : 'Update Split'),
      ),
    );
  }
}