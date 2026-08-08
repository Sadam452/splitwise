import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'group_details_screen.dart';
import 'auth_screen.dart';
import 'account_screen.dart';
import 'friends_screen.dart';
import 'activity_screen.dart';

final userGroupsProvider = StreamProvider<List<QueryDocumentSnapshot>>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  if (user == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('groups')
      .where('members', arrayContains: user.uid)
      .snapshots()
      .map((snapshot) => snapshot.docs);
});

final pendingInvitesProvider = StreamProvider<List<QueryDocumentSnapshot>>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  if (user == null || user.email == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('invitations')
      .where('inviteeEmail', isEqualTo: user.email!.toLowerCase())
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((snapshot) => snapshot.docs);
});

class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  int _currentIndex = 0;
  final Color _tealAccent = const Color(0xFF1CC29F);

  void _showCreateGroupDialog(BuildContext context) {
    final nameController = TextEditingController();
    final invitesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create New Group', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Group Name (e.g., Flat 402)',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: invitesController,
              decoration: InputDecoration(
                labelText: 'Invite Emails (comma separated)',
                hintText: 'user1@test.com, user2@test.com',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _tealAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              
              final user = FirebaseAuth.instance.currentUser!;
              final db = FirebaseFirestore.instance;
              
              final groupRef = db.collection('groups').doc();
              await groupRef.set({
                'groupId': groupRef.id,
                'name': nameController.text.trim(),
                'members': [user.uid],
                'createdBy': user.uid, 
              });

              final emails = invitesController.text.split(',')
                  .map((e) => e.trim().toLowerCase())
                  .where((e) => e.isNotEmpty);
                  
              for (var email in emails) {
                await db.collection('invitations').add({
                  'groupId': groupRef.id,
                  'groupName': nameController.text.trim(),
                  'inviteeEmail': email,
                  'status': 'pending',
                });
              }
              
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showInvitesDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pending Invitations'),
        content: Consumer(
          builder: (context, ref, child) {
            final invitesAsync = ref.watch(pendingInvitesProvider);
            
            return invitesAsync.when(
              data: (invites) {
                if (invites.isEmpty) return const Text('No pending invites.', style: TextStyle(color: Colors.grey));
                
                return SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: invites.length,
                    itemBuilder: (context, index) {
                      final invite = invites[index].data() as Map<String, dynamic>;
                      final inviteId = invites[index].id;
                      
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(invite['groupName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _tealAccent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final user = FirebaseAuth.instance.currentUser!;
                            final db = FirebaseFirestore.instance;
                            final batch = db.batch();

                            batch.update(db.collection('invitations').doc(inviteId), {'status': 'accepted'});
                            batch.update(db.collection('groups').doc(invite['groupId']), {
                              'members': FieldValue.arrayUnion([user.uid])
                            });

                            await batch.commit();
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('Accept'),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => Center(child: CircularProgressIndicator(color: _tealAccent)),
              error: (e, _) => Text('Error: $e'),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(userGroupsProvider);
    final invitesAsync = ref.watch(pendingInvitesProvider);
    final currentUser = FirebaseAuth.instance.currentUser;
    final photoUrl = currentUser?.photoURL;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 1),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/icon.png',
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7722).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.volunteer_activism_rounded, color: Color(0xFFFF6600), size: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Chanda',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                letterSpacing: -0.5,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        actions: [
          invitesAsync.maybeWhen(
            data: (invites) => IconButton(
              icon: Badge(
                isLabelVisible: invites.isNotEmpty,
                label: Text(invites.length.toString()),
                backgroundColor: Colors.red,
                child: const Icon(Icons.group_add_outlined, color: Colors.black87),
              ),
              onPressed: () => _showCreateGroupDialog(context),
            ),
            orElse: () => IconButton(
              icon: const Icon(Icons.group_add_outlined, color: Colors.black87),
              onPressed: () => _showCreateGroupDialog(context),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Replace your current body: with this:
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Groups (Your existing dashboard)
          groupsAsync.when(
            data: (groups) {
              if (groups.isEmpty) {
                return Center(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _tealAccent,
                      side: BorderSide(color: _tealAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () => _showCreateGroupDialog(context),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Start a new group', style: TextStyle(fontSize: 16)),
                  ),
                );
              }
              return GroupsDashboardBuilder(groups: groups, onCreateGroup: () => _showCreateGroupDialog(context));
            },
            loading: () => Center(child: CircularProgressIndicator(color: _tealAccent)),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
          
          // Tab 1: Friends
          const FriendsScreen(),
          
          // Tab 2: Activity
          const ActivityScreen(),
          
          // Tab 3: Account
          const AccountScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          // if (index == 3) {
          //   // Sign out purely for testing purposes on the account tab
          //   //FirebaseAuth.instance.signOut();
          // }
          setState(() => _currentIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _tealAccent,
        unselectedItemColor: Colors.grey.shade500,
        showUnselectedLabels: true,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.group),
            label: 'Groups',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Friends',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'Activity',
          ),
          BottomNavigationBarItem(
            icon: photoUrl != null 
                ? CircleAvatar(radius: 12, backgroundImage: NetworkImage(photoUrl))
                : const Icon(Icons.account_circle_outlined),
            activeIcon: photoUrl != null 
                ? CircleAvatar(radius: 12, backgroundImage: NetworkImage(photoUrl), child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _tealAccent, width: 2))))
                : const Icon(Icons.account_circle),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DYNAMIC DASHBOARD ENGINE
// Listens to all group orders real-time to calculate accurate overall and per-group balances.
// -----------------------------------------------------------------------------
class GroupsDashboardBuilder extends StatefulWidget {
  final List<QueryDocumentSnapshot> groups;
  final VoidCallback onCreateGroup;

  const GroupsDashboardBuilder({super.key, required this.groups, required this.onCreateGroup});

  @override
  State<GroupsDashboardBuilder> createState() => _GroupsDashboardBuilderState();
}

class _GroupsDashboardBuilderState extends State<GroupsDashboardBuilder> {
  final Color _tealAccent = const Color(0xFF1CC29F);
  final Color _redAccent = Colors.red.shade400;
  
  bool _isLoading = true;
  double _overallBalance = 0.0;
  
  // groupId -> List of Orders
  final Map<String, List<QueryDocumentSnapshot>> _groupOrders = {};
  
  // Subscriptions to keep the home screen live
  final Map<String, StreamSubscription> _orderSubscriptions = {};
  
  // Map of User UIDs to their names (resolved once)
  final Map<String, String> _memberNames = {};
  
  // Processed Data per group
  final Map<String, Map<String, dynamic>> _groupBalances = {};

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void didUpdateWidget(covariant GroupsDashboardBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-initialize if the user joins or leaves a group
    if (oldWidget.groups.length != widget.groups.length) {
      _initializeData();
    }
  }

  @override
  void dispose() {
    for (var sub in _orderSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _initializeData() async {
    final db = FirebaseFirestore.instance;
    
    // 1. Fetch all unique members across all groups to resolve names
    Set<String> uniqueUids = {};
    for (var g in widget.groups) {
      final members = List<dynamic>.from(g['members'] ?? []);
      uniqueUids.addAll(members.cast<String>());
    }

    for (String uid in uniqueUids) {
      if (!_memberNames.containsKey(uid)) {
        try {
          final doc = await db.collection('users').doc(uid).get();
          final data = doc.data() ?? {};
          String name = 'Unknown';
          if (data['firstName'] != null && data['firstName'].toString().isNotEmpty) {
            name = data['firstName'];
          } else if (data['email'] != null) {
            name = data['email'].toString().split('@').first;
          }
          _memberNames[uid] = name;
        } catch (_) {
          _memberNames[uid] = 'User';
        }
      }
    }

    // 2. Set up real-time listeners for all group orders
    for (var g in widget.groups) {
      final groupId = g.id;
      if (!_orderSubscriptions.containsKey(groupId)) {
        _orderSubscriptions[groupId] = db
            .collection('groups')
            .doc(groupId)
            .collection('orders')
            .snapshots()
            .listen((snapshot) {
          _groupOrders[groupId] = snapshot.docs;
          _calculateBalances();
        });
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // Exact math replica from GroupDetailsScreen to ensure perfect consistency
  Map<String, Map<String, double>> _calculateGroupDebts(List<QueryDocumentSnapshot> orderDocs, List<dynamic> memberIds) {
    Map<String, Map<String, double>> grossDebts = {
      for (var uid in memberIds)
        uid: { for (var other in memberIds) if (uid != other) other: 0.0 },
    };

    for (var doc in orderDocs) {
      final orderData = doc.data() as Map<String, dynamic>;
      if (orderData['status'] == 'deleted') continue;

      final payer = orderData['addedBy'];
      if (!memberIds.contains(payer)) continue;

      final items = orderData['items'] as List<dynamic>? ?? [];
      Map<String, double> orderSplits = {for (var uid in memberIds) uid: 0.0};

      final exactAmounts = orderData['exactAmounts'] as Map<String, dynamic>?;
      if (orderData['splitType'] == 'unequal' && exactAmounts != null) {
        exactAmounts.forEach((uid, amount) {
          if (orderSplits.containsKey(uid)) {
            orderSplits[uid] = (amount as num).toDouble();
          }
        });
      } else {
        for (var item in items) {
          List<String> splitBetween = List<String>.from(item['splitBetween'] ?? memberIds);
          if (splitBetween.isEmpty) splitBetween = List<String>.from(memberIds);

          double itemPrice = (item['price'] ?? 0).toDouble();
          int count = splitBetween.length;

          double baseSplit = double.parse((itemPrice / count).toStringAsFixed(2));
          double remainder = itemPrice - (baseSplit * (count - 1));

          for (int i = 0; i < count; i++) {
            String uid = splitBetween[i];
            double amountToAdd = (i == count - 1) ? remainder : baseSplit;
            if (orderSplits.containsKey(uid)) {
              orderSplits[uid] = orderSplits[uid]! + amountToAdd;
            }
          }
        }
      }

      for (var uid in memberIds) {
        if (uid != payer) {
          grossDebts[uid]![payer] = (grossDebts[uid]![payer] ?? 0.0) + orderSplits[uid]!;
        }
      }
    }

    Map<String, Map<String, double>> netDebts = {
      for (var uid in memberIds) uid: {},
    };
    
    for (int i = 0; i < memberIds.length; i++) {
      for (int j = i + 1; j < memberIds.length; j++) {
        String userA = memberIds[i];
        String userB = memberIds[j];

        double aOwesB = grossDebts[userA]![userB] ?? 0.0;
        double bOwesA = grossDebts[userB]![userA] ?? 0.0;
        double net = aOwesB - bOwesA;

        if (net > 0) {
          netDebts[userA]![userB] = net;
          netDebts[userB]![userA] = 0.0;
        } else if (net < 0) {
          netDebts[userB]![userA] = -net;
          netDebts[userA]![userB] = 0.0;
        } else {
          netDebts[userA]![userB] = 0.0;
          netDebts[userB]![userA] = 0.0;
        }
      }
    }
    return netDebts;
  }

  void _calculateBalances() {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserUid == null) return;

    double tempOverallBalance = 0.0;

    for (var g in widget.groups) {
      final groupId = g.id;
      final memberIds = List<dynamic>.from(g['members'] ?? []);
      final orders = _groupOrders[groupId] ?? [];

      final netDebts = _calculateGroupDebts(orders, memberIds);
      
      double groupTotalOwedToUser = 0.0;
      double groupTotalUserOwes = 0.0;
      
      Map<String, double> owesUserMap = {};
      Map<String, double> userOwesMap = {};

      for (var otherUid in memberIds) {
        if (otherUid == currentUserUid) continue;
        
        // Debt owed TO the current user
        double owesMe = netDebts[otherUid]?[currentUserUid] ?? 0.0;
        if (owesMe > 0) {
          groupTotalOwedToUser += owesMe;
          owesUserMap[otherUid] = owesMe;
        }
        
        // Debt the current user owes TO others
        double iOweThem = netDebts[currentUserUid]?[otherUid] ?? 0.0;
        if (iOweThem > 0) {
          groupTotalUserOwes += iOweThem;
          userOwesMap[otherUid] = iOweThem;
        }
      }

      double groupNet = groupTotalOwedToUser - groupTotalUserOwes;
      tempOverallBalance += groupNet;

      // Sort maps to get the top 2 highest debts
      var sortedOwesUser = owesUserMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      var sortedUserOwes = userOwesMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      _groupBalances[groupId] = {
        'net': groupNet,
        'topOwesUser': sortedOwesUser.take(2).toList(),
        'topUserOwes': sortedUserOwes.take(2).toList(),
      };
    }

    if (mounted) {
      setState(() {
        _overallBalance = tempOverallBalance;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _tealAccent));
    }

    // Determine the overall message and color
    String overallMessage = 'Overall, you are settled up';
    Color overallColor = Colors.grey.shade600;
    
    if (_overallBalance > 0.01) {
      overallMessage = 'Overall, you are owed ';
      overallColor = _tealAccent;
    } else if (_overallBalance < -0.01) {
      overallMessage = 'Overall, you owe ';
      overallColor = _redAccent;
    }

    return Column(
      children: [
        // Overall Balance Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _overallBalance.abs() < 0.01 
              ? Text(overallMessage, style: TextStyle(fontSize: 16, color: Colors.grey.shade600))
              : RichText(
                  text: TextSpan(
                    text: overallMessage,
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                    children: [
                      TextSpan(
                        text: '₹${_overallBalance.abs().toStringAsFixed(2)}',
                        style: TextStyle(color: overallColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
          ),
        ),
        
        const Divider(height: 1, color: Colors.black12),

        // Scrollable Groups List
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              ...widget.groups.map((groupDoc) {
                final group = groupDoc.data() as Map<String, dynamic>;
                final groupId = groupDoc.id;
                
                final balanceData = _groupBalances[groupId] ?? {'net': 0.0, 'topOwesUser': <MapEntry<String, double>>[], 'topUserOwes': <MapEntry<String, double>>[]};
                final double net = balanceData['net'];
                final topOwesUser = balanceData['topOwesUser'] as List<MapEntry<String, double>>;
                final topUserOwes = balanceData['topUserOwes'] as List<MapEntry<String, double>>;
                
                // Color and Gradients
                Color amountColor = Colors.grey.shade500;
                String groupSubtext = 'settled up';
                List<Widget> breakdownWidgets = [];
                
                if (net > 0.01) {
                  amountColor = _tealAccent;
                  groupSubtext = 'you are owed ₹${net.toStringAsFixed(2)}';
                  for (var entry in topOwesUser) {
                    final name = _memberNames[entry.key] ?? 'Someone';
                    breakdownWidgets.add(
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: RichText(
                          text: TextSpan(
                            text: '$name owes you ',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            children: [TextSpan(text: '₹${entry.value.toStringAsFixed(2)}', style: TextStyle(color: _tealAccent))],
                          ),
                        ),
                      )
                    );
                  }
                } else if (net < -0.01) {
                  amountColor = _redAccent;
                  groupSubtext = 'you owe ₹${(-net).toStringAsFixed(2)}';
                  for (var entry in topUserOwes) {
                    final name = _memberNames[entry.key] ?? 'Someone';
                    breakdownWidgets.add(
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: RichText(
                          text: TextSpan(
                            text: 'you owe $name ',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            children: [TextSpan(text: '₹${entry.value.toStringAsFixed(2)}', style: TextStyle(color: _redAccent))],
                          ),
                        ),
                      )
                    );
                  }
                }

                // Generates a distinct color gradient based on the group name so they look varied
                final gradientColors = (group['name'].toString().length % 2 == 0) 
                    ? const [Color(0xFFFF9933), Color(0xFFFF6600)] // Saffron 
                    : const [Color(0xFF2193b0), Color(0xFF6dd5ed)]; // Blue

                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GroupDetailsScreen(groupId: groupId, groupName: group['name']),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Square Icon
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.list_alt_rounded, color: Colors.white, size: 32),
                        ),
                        const SizedBox(width: 16),
                        
                        // Text Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(group['name'], style: const TextStyle(fontSize: 18, color: Colors.black87)),
                              const SizedBox(height: 2),
                              Text(groupSubtext, style: TextStyle(fontSize: 14, color: amountColor, fontWeight: FontWeight.w500)),
                              ...breakdownWidgets,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              
              const SizedBox(height: 24),
              
              Center(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _tealAccent,
                    side: BorderSide(color: _tealAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: widget.onCreateGroup,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Start a new group', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}