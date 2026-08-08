import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'groups_screen.dart'; // To access userGroupsProvider

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final Color _tealAccent = const Color(0xFF1CC29F);
  final Color _redAccent = Colors.red.shade400;

  bool _isLoading = true;
  double _overallBalance = 0.0;
  
  // Friend UID -> Net Balance (Positive means they owe you, negative means you owe them)
  final Map<String, double> _friendBalances = {};
  final Map<String, String> _friendNames = {};
  final Map<String, String?> _friendPhotos = {};

  @override
  void initState() {
    super.initState();
    // Delay slightly to let the Riverpod provider initialize
    Future.microtask(() => _calculateFriendsData());
  }

  Future<void> _calculateFriendsData() async {
    final groupsDocs = ref.read(userGroupsProvider).value ?? [];
    if (groupsDocs.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserUid == null) return;

    final db = FirebaseFirestore.instance;
    Map<String, double> tempFriendBalances = {};
    Set<String> allFriendUids = {};
    double tempOverall = 0.0;

    // 1. Fetch all orders for all groups and aggregate balances
    for (var g in groupsDocs) {
      final groupId = g.id;
      final memberIds = List<dynamic>.from(g['members'] ?? []);
      allFriendUids.addAll(memberIds.cast<String>());

      final ordersSnapshot = await db.collection('groups').doc(groupId).collection('orders').get();
      final netDebts = _calculateGroupDebts(ordersSnapshot.docs, memberIds);

      for (var otherUid in memberIds) {
        if (otherUid == currentUserUid) continue;
        
        double owesMe = netDebts[otherUid]?[currentUserUid] ?? 0.0;
        double iOweThem = netDebts[currentUserUid]?[otherUid] ?? 0.0;
        
        double netContribution = owesMe - iOweThem;
        
        tempFriendBalances[otherUid] = (tempFriendBalances[otherUid] ?? 0.0) + netContribution;
        tempOverall += netContribution;
      }
    }

    // 2. Fetch profiles for all friends
    allFriendUids.remove(currentUserUid);
    for (String uid in allFriendUids) {
      if (!_friendNames.containsKey(uid)) {
        try {
          final doc = await db.collection('users').doc(uid).get();
          final data = doc.data() ?? {};
          String name = 'Unknown';
          if (data['firstName'] != null && data['firstName'].toString().isNotEmpty) {
            name = data['firstName'];
          } else if (data['email'] != null) {
            name = data['email'].toString().split('@').first;
          }
          _friendNames[uid] = name;
          _friendPhotos[uid] = data['photoURL'] ?? data['photoUrl'];
        } catch (_) {
          _friendNames[uid] = 'User';
        }
      }
    }

    if (mounted) {
      setState(() {
        _friendBalances.clear();
        _friendBalances.addAll(tempFriendBalances);
        _overallBalance = tempOverall;
        _isLoading = false;
      });
    }
  }

  // Same math engine used in the rest of the app
  Map<String, Map<String, double>> _calculateGroupDebts(List<QueryDocumentSnapshot> orderDocs, List<dynamic> memberIds) {
    Map<String, Map<String, double>> grossDebts = {
      for (var uid in memberIds) uid: { for (var other in memberIds) if (uid != other) other: 0.0 },
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
        exactAmounts.forEach((uid, amount) => orderSplits[uid] = (amount as num).toDouble());
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
            orderSplits[uid] = (orderSplits[uid] ?? 0.0) + ((i == count - 1) ? remainder : baseSplit);
          }
        }
      }

      for (var uid in memberIds) {
        if (uid != payer) {
          grossDebts[uid]![payer] = (grossDebts[uid]![payer] ?? 0.0) + orderSplits[uid]!;
        }
      }
    }

    Map<String, Map<String, double>> netDebts = {for (var uid in memberIds) uid: {}};
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

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<QueryDocumentSnapshot>>>(
      userGroupsProvider,
      (previous, next) {
        if (next.value != null && next.value!.isNotEmpty) {
          _calculateFriendsData();
        }
      },
    );
    if (_isLoading) return Scaffold(backgroundColor: Colors.white, body: Center(child: CircularProgressIndicator(color: _tealAccent)));

    String overallMessage = 'Overall, you are settled up';
    Color overallColor = Colors.grey.shade600;
    if (_overallBalance > 0.01) {
      overallMessage = 'Overall, you are owed ';
      overallColor = _tealAccent;
    } else if (_overallBalance < -0.01) {
      overallMessage = 'Overall, you owe ';
      overallColor = _redAccent;
    }

    final sortedFriends = _friendBalances.keys.toList()
      ..sort((a, b) => _friendNames[a]!.compareTo(_friendNames[b]!));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: _overallBalance.abs() < 0.01 
              ? Text(overallMessage, style: TextStyle(fontSize: 16, color: Colors.grey.shade600))
              : RichText(
                  text: TextSpan(
                    text: overallMessage,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                    children: [
                      TextSpan(
                        text: '₹${_overallBalance.abs().toStringAsFixed(2)}',
                        style: TextStyle(color: overallColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
          ),
          const Divider(height: 24, color: Colors.black12),
          Expanded(
            child: sortedFriends.isEmpty 
              ? Center(child: Text("You don't have any friends in groups yet.", style: TextStyle(color: Colors.grey.shade500)))
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: sortedFriends.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 72, color: Colors.black12),
                  itemBuilder: (context, index) {
                    final uid = sortedFriends[index];
                    final name = _friendNames[uid] ?? 'User';
                    final photo = _friendPhotos[uid];
                    final balance = _friendBalances[uid] ?? 0.0;

                    String status = 'settled up';
                    Color statusColor = Colors.grey.shade500;
                    if (balance > 0.01) {
                      status = 'owes you\n₹${balance.toStringAsFixed(2)}';
                      statusColor = _tealAccent;
                    } else if (balance < -0.01) {
                      status = 'you owe\n₹${(-balance).toStringAsFixed(2)}';
                      statusColor = _redAccent;
                    }

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: photo != null ? NetworkImage(photo) : null,
                        child: photo == null ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)) : null,
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                      trailing: Text(
                        status,
                        textAlign: TextAlign.right,
                        style: TextStyle(color: statusColor, fontWeight: balance.abs() > 0.01 ? FontWeight.w600 : FontWeight.normal, fontSize: 13),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}