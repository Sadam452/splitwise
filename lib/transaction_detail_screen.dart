import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_split_screen.dart';
import 'edit_bill_details_screen.dart';

class TransactionDetailScreen extends StatelessWidget {
  final String groupId;
  final String orderId;
  final Map<String, dynamic> orderData;
  final Map<String, dynamic> membersData;

  const TransactionDetailScreen({
    super.key,
    required this.groupId,
    required this.orderId,
    required this.orderData,
    required this.membersData,
  });

  String _getUserName(String uid) {
    final userData = membersData[uid];
    if (userData == null) return 'Unknown';
    if (userData['firstName'] != null && userData['firstName'].toString().isNotEmpty) {
      return userData['firstName'];
    }
    final email = userData['email']?.toString() ?? 'User';
    return email.split('@').first;
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    return "${date.day}/${date.month}/${date.year}";
  }

  Future<void> _deleteTransaction(BuildContext context, bool isSettlement) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isSettlement ? 'Cancel Settlement' : 'Delete Transaction'),
        content: Text(
          isSettlement 
              ? 'Are you sure you want to delete this settlement? The debt will be restored to your balances.' 
              : 'Are you sure you want to delete this bill? It will still be visible in the history but will not count towards group balances.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
      
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('orders')
          .doc(orderId)
          .update({
        'status': 'deleted',
        'deletedBy': currentUserUid,
        'deletedAt': FieldValue.serverTimestamp(),
      });
      
      if (context.mounted) Navigator.pop(context);
    }
  }

  Map<String, double> _calculateSplits(List<String> memberIds, Map<String, dynamic> currentOrderData) {
    Map<String, double> balances = {for (var uid in memberIds) uid: 0.0};
    
    final exactAmounts = currentOrderData['exactAmounts'] as Map<String, dynamic>?;
    if (currentOrderData['splitType'] == 'unequal' && exactAmounts != null) {
      exactAmounts.forEach((uid, amount) {
        balances[uid] = (amount as num).toDouble();
      });
      return balances;
    }
    
    final items = currentOrderData['items'] as List<dynamic>? ?? [];
    for (var item in items) {
      List<String> splitBetween = List<String>.from(item['splitBetween'] ?? memberIds);
      if (splitBetween.isEmpty) splitBetween = memberIds; 
      
      double itemPrice = (item['price'] ?? 0).toDouble();
      int count = splitBetween.length;
      
      double baseSplit = double.parse((itemPrice / count).toStringAsFixed(2));
      double remainder = itemPrice - (baseSplit * (count - 1));

      for (int i = 0; i < count; i++) {
        String uid = splitBetween[i];
        double amountToAdd = (i == count - 1) ? remainder : baseSplit;
        
        if (balances.containsKey(uid)) {
          balances[uid] = balances[uid]! + amountToAdd;
        }
      }
    }
    return balances;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('orders')
          .doc(orderId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Scaffold(body: Center(child: Text('Error: ${snapshot.error}')));
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final freshOrderData = snapshot.data?.data() as Map<String, dynamic>? ?? orderData;
        final isCreator = currentUserUid == freshOrderData['addedBy'];
        final isDeleted = freshOrderData['status'] == 'deleted';

        final title = freshOrderData['title'] ?? 'Untitled Order';
        final isSettlement = title.toString().startsWith('💸 Settlement'); 
        
        final totalAmount = freshOrderData['total_amount'] ?? 0.0;
        
        final addedByUid = freshOrderData['addedBy'];
        final updatedByUid = freshOrderData['updatedBy'];
        final addedByName = _getUserName(addedByUid);
        final updatedByName = updatedByUid != null ? _getUserName(updatedByUid) : addedByName;
        
        final addedDate = _formatDate(freshOrderData['timestamp'] as Timestamp?);
        final updatedDate = _formatDate(freshOrderData['updatedAt'] as Timestamp?) == '' 
            ? addedDate 
            : _formatDate(freshOrderData['updatedAt'] as Timestamp?);

        final memberIds = membersData.keys.toList();
        final calculatedBalances = _calculateSplits(memberIds, freshOrderData);

        return Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (!isSettlement && !isDeleted)
                IconButton(
                  icon: Icon(
                    Icons.edit, 
                    color: isCreator ? Colors.deepPurple : Colors.grey.shade300
                  ),
                  onPressed: isCreator 
                      ? () {
                          // Navigates instantly to details screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditBillDetailsScreen(
                                groupId: groupId,
                                orderId: orderId,
                                orderData: freshOrderData, 
                              ),
                            ),
                          );
                        }
                      : null,
                  tooltip: isCreator ? 'Edit Bill Details' : 'Only the creator can edit details',
                ),
                
              if (!isDeleted)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline, 
                    color: isCreator ? Colors.red : Colors.grey.shade300
                  ),
                  onPressed: isCreator ? () => _deleteTransaction(context, isSettlement) : null,
                  tooltip: isCreator ? (isSettlement ? 'Cancel Settlement' : 'Delete Transaction') : 'Only the creator can delete this',
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
                    ]
                  ),
                  child: Column(
                    children: [
                      if (isSettlement) 
                         const Icon(Icons.handshake_rounded, size: 48, color: Colors.blue),
                      const SizedBox(height: 8),
                      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Text(
                        '₹${totalAmount.toStringAsFixed(2)}', 
                        style: TextStyle(
                          fontSize: 32, 
                          fontWeight: FontWeight.w900, 
                          color: isSettlement ? Colors.blue.shade700 : Colors.deepPurple,
                          decoration: isDeleted ? TextDecoration.lineThrough : null,
                        )
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isSettlement ? 'Paid via $addedByName' : 'Paid by $addedByName', 
                          style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                Text('Added by $addedByName on $addedDate', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                if (updatedByUid != null && !isSettlement)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Last updated by $updatedByName on $updatedDate', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ),
                if (isDeleted)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Deleted by ${_getUserName(freshOrderData['deletedBy'])}', style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),

                const SizedBox(height: 24),
                Text(isSettlement ? 'Settlement Details' : 'Split Details', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: memberIds.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final uid = memberIds[index];
                      final name = _getUserName(uid);
                      final isPayer = uid == addedByUid;
                      
                      final shareAmount = calculatedBalances[uid] ?? 0.0;
                      
                      if (isSettlement && shareAmount == 0 && !isPayer) return const SizedBox.shrink();

                      String settlementText = '';
                      Color settlementColor = Colors.grey.shade600;

                      if (isPayer) {
                        double getsBack = totalAmount - shareAmount;
                        if (getsBack > 0) {
                          settlementText = isSettlement ? 'Paid the money' : 'Gets back ₹${getsBack.toStringAsFixed(2)}';
                          settlementColor = Colors.green;
                        } else {
                          settlementText = isSettlement ? 'Paid the money' : 'Paid entirely for self';
                        }
                      } else {
                        if (shareAmount > 0) {
                          settlementText = isSettlement ? 'Received ₹${shareAmount.toStringAsFixed(2)}' : 'Owes ₹${shareAmount.toStringAsFixed(2)}';
                          settlementColor = isSettlement ? Colors.blue.shade700 : Colors.red;
                        } else {
                          settlementText = 'Not in this bill';
                        }
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.deepPurple.shade100,
                          child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: !isSettlement ? Text('Share: ₹${shareAmount.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)) : null,
                        trailing: Text(
                          settlementText, 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: settlementColor)
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          
          floatingActionButton: (isSettlement || isDeleted) 
              ? null 
              : FloatingActionButton(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    // Navigates instantly to edit split screen without any locks
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditSplitScreen(
                          groupId: groupId,
                          orderId: orderId,
                          orderData: freshOrderData,
                          allMemberIds: membersData.keys.toList(),
                          membersData: membersData,
                        ),
                      ),
                    );
                  },
                  child: const Icon(Icons.splitscreen),
                ),
        );
      }
    );
  }
}