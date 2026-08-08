import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_split_screen.dart';
import 'edit_bill_details_screen.dart';

class TransactionDetailScreen extends StatefulWidget {
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

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late String _currentUserUid;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    _tabController = TabController(length: 2, vsync: this);
    
    // Rebuild to show/hide the comment input field when switching tabs
    _tabController.addListener(() {
      setState(() {});
    });

    _markAsReviewed();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Automatically tags the user as having seen/reviewed this bill
  Future<void> _markAsReviewed() async {
    final List<dynamic> reviewedBy = widget.orderData['reviewedBy'] ?? [];
    if (!reviewedBy.contains(_currentUserUid)) {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc(widget.orderId)
          .update({
        'reviewedBy': FieldValue.arrayUnion([_currentUserUid])
      });
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc(widget.orderId)
          .collection('activities')
          .add({
        'type': 'comment',
        'text': text,
        'userId': _currentUserUid,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      _commentController.clear();
      // Scroll to bottom after sending
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _getUserName(String uid) {
    final userData = widget.membersData[uid];
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
  String _formatActivityTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    
    // Get month name
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[date.month - 1];
    
    // Get 2-digit year
    final year = date.year.toString().substring(2);
    
    // Add st, nd, rd, th
    String daySuffix = 'th';
    if (!(date.day >= 11 && date.day <= 13)) {
      switch (date.day % 10) {
        case 1: daySuffix = 'st'; break;
        case 2: daySuffix = 'nd'; break;
        case 3: daySuffix = 'rd'; break;
      }
    }
    
    // 12-hour format time
    int hour = date.hour;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    final minute = date.minute.toString().padLeft(2, '0');
    
    return "${date.day}$daySuffix $month $year, $hour:$minute $ampm";
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
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc(widget.orderId)
          .update({
        'status': 'deleted',
        'deletedBy': _currentUserUid,
        'deletedAt': FieldValue.serverTimestamp(),
      });
      
      // Add a system log for the deletion
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc(widget.orderId)
          .collection('activities')
          .add({
        'type': 'system',
        'text': '${_getUserName(_currentUserUid)} deleted the bill.',
        'userId': _currentUserUid,
        'timestamp': FieldValue.serverTimestamp(),
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
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc(widget.orderId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Scaffold(body: Center(child: Text('Error: ${snapshot.error}')));
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final freshOrderData = snapshot.data?.data() as Map<String, dynamic>? ?? widget.orderData;
        final isCreator = _currentUserUid == freshOrderData['addedBy'];
        final isDeleted = freshOrderData['status'] == 'deleted';
        final title = freshOrderData['title'] ?? 'Untitled Order';
        final isSettlement = title.toString().startsWith('💸 Settlement'); 
        final totalAmount = freshOrderData['total_amount'] ?? 0.0;
        final addedByUid = freshOrderData['addedBy'];
        final addedByName = _getUserName(addedByUid);

        return Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (!isSettlement && !isDeleted)
                IconButton(
                  icon: Icon(Icons.edit, color: isCreator ? Colors.deepPurple : Colors.grey.shade300),
                  onPressed: isCreator ? () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditBillDetailsScreen(groupId: widget.groupId, orderId: widget.orderId, orderData: freshOrderData))) : null,
                ),
              if (!isDeleted)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: isCreator ? Colors.red : Colors.grey.shade300),
                  onPressed: isCreator ? () => _deleteTransaction(context, isSettlement) : null,
                ),
            ],
          ),
          body: Column(
            children: [
              // Fixed Top Summary Card
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    if (isSettlement) const Icon(Icons.handshake_rounded, size: 48, color: Colors.blue),
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
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        isSettlement ? 'Paid via $addedByName' : 'Paid by $addedByName', 
                        style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

              // Sticky Tab Bar
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.deepPurple,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.deepPurple,
                  tabs: const [
                    Tab(text: 'Activity'),
                    Tab(text: 'Split Details'),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.black12),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildActivityTab(),
                    _buildSplitDetailsTab(freshOrderData, isSettlement, isDeleted),
                  ],
                ),
              ),
              
              // Input Field (Only visible on Activity Tab)
              if (_tabController.index == 0) _buildCommentInput(),
            ],
          ),
          floatingActionButton: (_tabController.index == 1 && !isSettlement && !isDeleted) 
              ? FloatingActionButton.extended(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditSplitScreen(groupId: widget.groupId, orderId: widget.orderId, orderData: freshOrderData, allMemberIds: widget.membersData.keys.toList(), membersData: widget.membersData))),
                  icon: const Icon(Icons.splitscreen),
                  label: const Text('Edit My Split'),
                )
              : null,
        );
      }
    );
  }

  Widget _buildActivityTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc(widget.orderId)
          .collection('activities')
          .orderBy('timestamp', descending: true) // Order descending so new messages appear at the bottom natively
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Error loading activity.'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data?.docs ?? [];
        
        if (docs.isEmpty) {
          return Center(
            child: Text('No activity yet.', style: TextStyle(color: Colors.grey.shade500)),
          );
        }

        return ListView.separated(
          controller: _scrollController,
          reverse: true, // Flips the list so the bottom is the latest
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final isSystem = data['type'] == 'system';
            final isMe = data['userId'] == _currentUserUid;
            final senderName = _getUserName(data['userId'] ?? '');
            
            // Format the timestamp using our new helper
            final timeString = _formatActivityTime(data['timestamp'] as Timestamp?);

            // 1. WhatsApp-style System Logs
// 1. WhatsApp-style System Logs
            if (isSystem) {
              return Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200, 
                    borderRadius: BorderRadius.circular(16)
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        data['text'] ?? '', 
                        style: const TextStyle(fontSize: 15, color: Colors.black87), // Matches regular comment size
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2), // Tiny gap
                      Text(
                        timeString,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 9, // Extra small font matching the chat bubble subtitle
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // 2. WhatsApp-style Chat Bubbles
            // 2. WhatsApp-style Chat Bubbles
            return Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4), // Spacing between bubbles
                  padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 6),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.deepPurple : Colors.white,
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                      bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(16),
                    ),
                    border: isMe ? null : Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Sender Name (Only for other users, inside the bubble)
                      if (!isMe)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              senderName,
                              style: TextStyle(
                                fontSize: 12, 
                                color: Colors.deepPurple.shade600, // Distinct color for names
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        
                      // The actual message
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          data['text'] ?? '',
                          style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15),
                        ),
                      ),
                      
                      const SizedBox(height: 2), 
                      
                      // Timestamp Subtitle
                      Text(
                        timeString,
                        style: TextStyle(
                          color: isMe ? Colors.white60 : Colors.grey.shade500,
                          fontSize: 9, 
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            },
          );
      },
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 16, 
        right: 16, 
        top: 12, 
        bottom: MediaQuery.of(context).padding.bottom + 12
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: 'Add a comment...',
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendComment(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.deepPurple,
            child: IconButton(
              icon: _isSending 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: _isSending ? null : _sendComment,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSplitDetailsTab(Map<String, dynamic> freshOrderData, bool isSettlement, bool isDeleted) {
    final memberIds = widget.membersData.keys.toList();
    final calculatedBalances = _calculateSplits(memberIds, freshOrderData);
    final addedByUid = freshOrderData['addedBy'];
    final totalAmount = freshOrderData['total_amount'] ?? 0.0;
    
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: memberIds.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
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

        // Action Indicator (Has the user reviewed this?)
        final reviewedBy = List<String>.from(freshOrderData['reviewedBy'] ?? []);
        final hasReviewed = reviewedBy.contains(uid);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: Colors.deepPurple.shade50,
              child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    name, 
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasReviewed && !isSettlement) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.done_all_rounded, size: 16, color: Colors.green)
                ]
              ],
            ),
            subtitle: !isSettlement ? Text('Share: ₹${shareAmount.toStringAsFixed(2)}') : null,
            trailing: Text(
              settlementText, 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: settlementColor)
            ),
          ),
        );
      },
    );
  }
}