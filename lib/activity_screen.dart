import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'groups_screen.dart'; // To access userGroupsProvider

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final Color _tealAccent = const Color(0xFF1CC29F);
  final Color _redAccent = Colors.red.shade400;

  bool _isLoading = true;
  List<Map<String, dynamic>> _unifiedFeed = [];
  final Map<String, String> _userNames = {};
  final Map<String, String> _groupNames = {};
  final Map<String, String> _orderTitles = {}; // Cache for order titles

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetchUnifiedActivities());
  }

Future<void> _fetchUnifiedActivities() async {
    final groupsDocs = ref.read(userGroupsProvider).value ?? [];
    if (groupsDocs.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserUid == null) return;

    final db = FirebaseFirestore.instance;
    List<Map<String, dynamic>> feedItems = [];
    Set<String> uidsToFetch = {};

    // 1. Fetch recent Orders for all groups
    for (var g in groupsDocs) {
      final groupId = g.id;
      _groupNames[groupId] = g['name'] ?? 'Unknown Group';

      final ordersSnapshot = await db
          .collection('groups')
          .doc(groupId)
          .collection('orders')
          .orderBy('timestamp', descending: true)
          .limit(15) // Get top 15 recent bills per group
          .get();
      
      for (var doc in ordersSnapshot.docs) {
        final order = doc.data();
        order['feed_type'] = 'order'; 
        order['groupId'] = groupId;
        order['orderId'] = doc.id;
        
        _orderTitles[doc.id] = order['title'] ?? 'an item';
        
        uidsToFetch.add(order['addedBy']);
        if (order['deletedBy'] != null) uidsToFetch.add(order['deletedBy']);
        
        feedItems.add(order);
      }
    }

    // 2. Fetch Comments & Edits directly from those recent orders (NO INDEX REQUIRED)
    // We create a copy of the list to loop through safely
    final currentOrders = List<Map<String, dynamic>>.from(feedItems);
    
    for (var order in currentOrders) {
      final groupId = order['groupId'];
      final orderId = order['orderId'];
      
      try {
        final activitiesSnapshot = await db
            .collection('groups')
            .doc(groupId)
            .collection('orders')
            .doc(orderId)
            .collection('activities')
            .orderBy('timestamp', descending: true)
            .get();
            
        for (var doc in activitiesSnapshot.docs) {
          final activityData = doc.data();
          activityData['feed_type'] = 'activity';
          activityData['groupId'] = groupId;
          activityData['orderId'] = orderId;
          
          uidsToFetch.add(activityData['userId'] ?? '');
          feedItems.add(activityData);
        }
      } catch (e) {
        debugPrint("Error fetching activities for order $orderId: $e");
      }
    }

    // 3. Resolve User Names
    for (String uid in uidsToFetch) {
      if (uid.isEmpty) continue;
      if (!_userNames.containsKey(uid)) {
        try {
          final doc = await db.collection('users').doc(uid).get();
          final data = doc.data() ?? {};
          _userNames[uid] = data['firstName'] ?? data['email']?.toString().split('@').first ?? 'Someone';
        } catch (_) {
          _userNames[uid] = 'User';
        }
      }
    }

    // 4. Sort everything chronologically (Newest at the top)
    feedItems.sort((a, b) {
      final Timestamp timeA = a['timestamp'] ?? Timestamp.now();
      final Timestamp timeB = b['timestamp'] ?? Timestamp.now();
      return timeB.compareTo(timeA); 
    });

    if (mounted) {
      setState(() {
        _unifiedFeed = feedItems;
        _isLoading = false;
      });
    }
  }
  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Just now';
    final date = timestamp.toDate();
    final now = DateTime.now();
    
    int hour = date.hour;
    final ampm = hour >= 12 ? 'pm' : 'am';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    final min = date.minute.toString().padLeft(2, '0');
    final timeString = '$hour:$min $ampm';

    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today, $timeString';
    } else if (date.year == now.year && date.month == now.month && date.day == now.day - 1) {
      return 'Yesterday, $timeString';
    }
    return '${date.day}/${date.month}/${date.year}, $timeString';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    ref.listen<AsyncValue<List<QueryDocumentSnapshot>>>(
      userGroupsProvider,
      (previous, next) {
        if (next.value != null && next.value!.isNotEmpty) {
          _fetchUnifiedActivities();
        }
      },
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Recent activity', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator(color: _tealAccent))
        : _unifiedFeed.isEmpty 
            ? Center(child: Text('No recent activity.', style: TextStyle(color: Colors.grey.shade500)))
            : ListView.separated(
                itemCount: _unifiedFeed.length,
                separatorBuilder: (context, index) => const Divider(height: 1, indent: 72, color: Colors.black12),
                itemBuilder: (context, index) {
                  final item = _unifiedFeed[index];
                  final feedType = item['feed_type']; // 'order' or 'activity'
                  final groupName = _groupNames[item['groupId']] ?? 'a group';
                  final orderTitle = _orderTitles[item['orderId']] ?? 'an item';
                  final timeText = _formatTime(item['timestamp'] as Timestamp?);

                  String actionText = '';
                  String subtitle = '';
                  Color subtitleColor = Colors.grey.shade500;
                  IconData iconData = Icons.circle;
                  Color iconColor = Colors.grey;
                  Color iconBg = Colors.grey.shade100;
                  String primaryName = '';

                  // --- 1. HANDLE BILLS (CREATED / DELETED) ---
                  if (feedType == 'order') {
                    final isDeleted = item['status'] == 'deleted';
                    final addedByUid = item['addedBy'];
                    final deletedByUid = item['deletedBy'];
                    
                    final addedByName = (addedByUid == currentUserUid) ? 'You' : (_userNames[addedByUid] ?? 'Someone');
                    final deletedByName = (deletedByUid == currentUserUid) ? 'You' : (_userNames[deletedByUid] ?? 'Someone');
                    primaryName = isDeleted ? deletedByName : addedByName;

                    if (isDeleted) {
                      actionText = 'deleted "$orderTitle" in "$groupName".';
                      iconData = Icons.delete_outline;
                      iconColor = Colors.grey.shade700;
                      iconBg = Colors.grey.shade200;
                    } else if (orderTitle.toString().startsWith('💸 Settlement')) {
                      actionText = 'recorded a payment in "$groupName".';
                      iconData = Icons.handshake_rounded;
                      iconColor = Colors.blue.shade600;
                      iconBg = Colors.blue.shade50;
                    } else {
                      actionText = 'added "$orderTitle" in "$groupName".';
                      iconData = Icons.receipt_long_rounded;
                      iconColor = _tealAccent;
                      iconBg = Colors.teal.shade50;
                      subtitle = 'Total: ₹${(item['total_amount'] ?? 0.0).toStringAsFixed(2)}';
                      subtitleColor = _redAccent;
                    }
                  } 
                  
                  // --- 2. HANDLE COMMENTS & SYSTEM EDITS ---
                  else if (feedType == 'activity') {
                    final activityType = item['type']; // 'comment' or 'system'
                    final userId = item['userId'];
                    primaryName = (userId == currentUserUid) ? 'You' : (_userNames[userId] ?? 'Someone');

                    if (activityType == 'comment') {
                      actionText = 'commented on "$orderTitle" in "$groupName".';
                      iconData = Icons.chat_bubble_outline_rounded;
                      iconColor = Colors.deepPurple;
                      iconBg = Colors.deepPurple.shade50;
                      subtitle = '"${item['text']}"'; // Show the actual comment text
                      subtitleColor = Colors.black87;
                    } else if (activityType == 'system') {
                      // System logs already have the name built-in (e.g., "Sadam updated their split details.")
                      // We replace the name with "You" if it's the current user to keep it clean.
                      final rawText = item['text'] ?? '';
                      final cleanText = (userId == currentUserUid) 
                          ? rawText.replaceFirst(_userNames[userId] ?? '', 'You') 
                          : rawText;
                          
                      primaryName = ''; // Handled entirely inside actionText
                      actionText = '$cleanText\n(in "$orderTitle")';
                      iconData = Icons.edit_note_rounded;
                      iconColor = Colors.orange.shade700;
                      iconBg = Colors.orange.shade50;
                    }
                  }

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                      child: Icon(iconData, color: iconColor, size: 24),
                    ),
                    title: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.3),
                        children: [
                          if (primaryName.isNotEmpty)
                            TextSpan(
                              text: primaryName == 'You' ? 'You ' : '${primaryName.split(' ')[0]} ', 
                              style: const TextStyle(fontWeight: FontWeight.bold)
                            ),
                          TextSpan(text: actionText),
                        ],
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 2),
                            child: Text(
                              subtitle, 
                              style: TextStyle(
                                color: subtitleColor, 
                                fontWeight: feedType == 'activity' ? FontWeight.normal : FontWeight.w500, 
                                fontStyle: feedType == 'activity' ? FontStyle.italic : FontStyle.normal,
                                fontSize: 13
                              )
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(timeText, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
    );
  }
}