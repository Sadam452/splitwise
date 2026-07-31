// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'group_details_screen.dart';
// import 'auth_screen.dart';

// // Stream of groups where the current user is in the 'members' array
// final userGroupsProvider = StreamProvider<List<QueryDocumentSnapshot>>((ref) {
//   final authState = ref.watch(authStateProvider);
//   final user = authState.value;
  
//   if (user == null) return const Stream.empty();

//   return FirebaseFirestore.instance
//       .collection('groups')
//       .where('members', arrayContains: user.uid)
//       .snapshots()
//       .map((snapshot) => snapshot.docs);
// });

// // Stream of pending invitations matching the user's email
// final pendingInvitesProvider = StreamProvider<List<QueryDocumentSnapshot>>((ref) {
//   final authState = ref.watch(authStateProvider);
//   final user = authState.value;
  
//   if (user == null || user.email == null) return const Stream.empty();

//   return FirebaseFirestore.instance
//       .collection('invitations')
//       .where('inviteeEmail', isEqualTo: user.email!.toLowerCase())
//       .where('status', isEqualTo: 'pending')
//       .snapshots()
//       .map((snapshot) => snapshot.docs);
// });

// class GroupsScreen extends ConsumerWidget {
//   const GroupsScreen({super.key});

//   void _showCreateGroupDialog(BuildContext context) {
//     final nameController = TextEditingController();
//     final invitesController = TextEditingController();

//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         title: const Text('Create New Group', style: TextStyle(fontWeight: FontWeight.bold)),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             TextField(
//               controller: nameController,
//               decoration: InputDecoration(
//                 labelText: 'Group Name (e.g., Flat 402)',
//                 filled: true,
//                 fillColor: Colors.grey.shade100,
//                 border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
//               ),
//             ),
//             const SizedBox(height: 12),
//             TextField(
//               controller: invitesController,
//               decoration: InputDecoration(
//                 labelText: 'Invite Emails (comma separated)',
//                 hintText: 'user1@test.com, user2@test.com',
//                 filled: true,
//                 fillColor: Colors.grey.shade100,
//                 border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
//               ),
//             ),
//           ],
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
//           ),
//           ElevatedButton(
//             style: ElevatedButton.styleFrom(
//               backgroundColor: const Color(0xFFFF7722), // Bhagwa Button
//               foregroundColor: Colors.white,
//               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//             ),
//             onPressed: () async {
//               if (nameController.text.isEmpty) return;
              
//               final user = FirebaseAuth.instance.currentUser!;
//               final db = FirebaseFirestore.instance;
              
//               final groupRef = db.collection('groups').doc();
//               await groupRef.set({
//                 'groupId': groupRef.id,
//                 'name': nameController.text.trim(),
//                 'members': [user.uid],
//                 'createdBy': user.uid, 
//               });

//               final emails = invitesController.text.split(',')
//                   .map((e) => e.trim().toLowerCase())
//                   .where((e) => e.isNotEmpty);
                  
//               for (var email in emails) {
//                 await db.collection('invitations').add({
//                   'groupId': groupRef.id,
//                   'groupName': nameController.text.trim(),
//                   'inviteeEmail': email,
//                   'status': 'pending',
//                 });
//               }
              
//               if (context.mounted) Navigator.pop(context);
//             },
//             child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold)),
//           ),
//         ],
//       ),
//     );
//   }

//   void _showInvitesDialog(BuildContext context, WidgetRef ref) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         title: const Text('Pending Invitations'),
//         content: Consumer(
//           builder: (context, ref, child) {
//             final invitesAsync = ref.watch(pendingInvitesProvider);
            
//             return invitesAsync.when(
//               data: (invites) {
//                 if (invites.isEmpty) return const Text('No pending invites.', style: TextStyle(color: Colors.grey));
                
//                 return SizedBox(
//                   width: double.maxFinite,
//                   child: ListView.builder(
//                     shrinkWrap: true,
//                     itemCount: invites.length,
//                     itemBuilder: (context, index) {
//                       final invite = invites[index].data() as Map<String, dynamic>;
//                       final inviteId = invites[index].id;
                      
//                       return ListTile(
//                         contentPadding: EdgeInsets.zero,
//                         title: Text(invite['groupName'], style: const TextStyle(fontWeight: FontWeight.bold)),
//                         trailing: ElevatedButton(
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: const Color(0xFFFF7722), // Bhagwa Accent
//                             foregroundColor: Colors.white,
//                           ),
//                           onPressed: () async {
//                             final user = FirebaseAuth.instance.currentUser!;
//                             final db = FirebaseFirestore.instance;
//                             final batch = db.batch();

//                             batch.update(db.collection('invitations').doc(inviteId), {'status': 'accepted'});
//                             batch.update(db.collection('groups').doc(invite['groupId']), {
//                               'members': FieldValue.arrayUnion([user.uid])
//                             });

//                             await batch.commit();
//                             if (context.mounted) Navigator.pop(context);
//                           },
//                           child: const Text('Accept'),
//                         ),
//                       );
//                     },
//                   ),
//                 );
//               },
//               loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF7722))),
//               error: (e, _) => Text('Error: $e'),
//             );
//           },
//         ),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final groupsAsync = ref.watch(userGroupsProvider);
//     final invitesAsync = ref.watch(pendingInvitesProvider);

//     return Scaffold(
//       backgroundColor: const Color(0xFFFFF8F2), // Very soft Bhagwa/Orange tint for the background
//       appBar: AppBar(
//         title: const Text('My Groups', style: TextStyle(fontWeight: FontWeight.w700)),
//         backgroundColor: Colors.white,
//         surfaceTintColor: Colors.transparent,
//         elevation: 0,
//         actions: [
//           invitesAsync.maybeWhen(
//             data: (invites) => IconButton(
//               icon: Badge(
//                 isLabelVisible: invites.isNotEmpty,
//                 label: Text(invites.length.toString()),
//                 backgroundColor: Colors.red,
//                 child: const Icon(Icons.notifications_none_rounded, color: Colors.black87),
//               ),
//               onPressed: () => _showInvitesDialog(context, ref),
//             ),
//             orElse: () => IconButton(
//               icon: const Icon(Icons.notifications_none_rounded, color: Colors.black87),
//               onPressed: () => _showInvitesDialog(context, ref),
//             ),
//           ),
//           IconButton(
//             icon: const Icon(Icons.logout_rounded, color: Colors.black87),
//             onPressed: () => FirebaseAuth.instance.signOut(),
//           ),
//           const SizedBox(width: 8),
//         ],
//       ),
//       body: groupsAsync.when(
//         data: (groups) {
//           if (groups.isEmpty) {
//             return Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Icon(Icons.groups_outlined, size: 80, color: Colors.orange.shade200),
//                   const SizedBox(height: 16),
//                   const Text('No groups yet.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
//                   const SizedBox(height: 8),
//                   Text('Create one to start splitting bills.', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
//                 ],
//               )
//             );
//           }
//           return ListView.builder(
//             padding: const EdgeInsets.only(top: 16, bottom: 100),
//             itemCount: groups.length,
//             itemBuilder: (context, index) {
//               final group = groups[index].data() as Map<String, dynamic>;
              
//               return Container(
//                 margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                 decoration: BoxDecoration(
//                   // Smooth Bhagwa (Saffron) Gradient
//                   gradient: const LinearGradient(
//                     colors: [Color(0xFFFF9933), Color(0xFFFF6600)], 
//                     begin: Alignment.topLeft,
//                     end: Alignment.bottomRight,
//                   ),
//                   borderRadius: BorderRadius.circular(20),
//                   boxShadow: [
//                     BoxShadow(
//                       color: const Color(0xFFFF6600).withOpacity(0.3),
//                       blurRadius: 12,
//                       offset: const Offset(0, 6),
//                     ),
//                   ],
//                 ),
//                 child: Material(
//                   color: Colors.transparent,
//                   child: InkWell(
//                     borderRadius: BorderRadius.circular(20),
//                     onTap: () {
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                           builder: (context) => GroupDetailsScreen(
//                             groupId: group['groupId'],
//                             groupName: group['name'],
//                           ),
//                         ),
//                       );
//                     },
//                     child: Padding(
//                       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
//                       child: Row(
//                         children: [
//                           // Icon before the group name
//                           Container(
//                             padding: const EdgeInsets.all(12),
//                             decoration: BoxDecoration(
//                               color: Colors.white.withOpacity(0.25),
//                               shape: BoxShape.circle,
//                             ),
//                             child: const Icon(Icons.groups_rounded, color: Colors.white, size: 32),
//                           ),
//                           const SizedBox(width: 16),
                          
//                           // Increased Group Name Text
//                           Expanded(
//                             child: Text(
//                               group['name'],
//                               style: const TextStyle(
//                                 fontSize: 24, // Increased size
//                                 fontWeight: FontWeight.w800,
//                                 color: Colors.white,
//                                 letterSpacing: 0.5,
//                               ),
//                               maxLines: 1,
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                           ),
                          
//                           // Smooth trailing arrow
//                           Container(
//                             padding: const EdgeInsets.all(8),
//                             decoration: BoxDecoration(
//                               color: Colors.white.withOpacity(0.15),
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                             child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 24),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               );
//             },
//           );
//         },
//         loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF7722))),
//         error: (e, _) => Center(child: Text('Error: $e')),
//       ),
//       floatingActionButton: FloatingActionButton.extended(
//         backgroundColor: const Color(0xFFFF6600), // Solid Bhagwa for the FAB
//         foregroundColor: Colors.white,
//         elevation: 4,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         onPressed: () => _showCreateGroupDialog(context),
//         icon: const Icon(Icons.add_rounded),
//         label: const Text('New Group', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
//       ),
//     );
//   }
// }
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'group_details_screen.dart';
import 'auth_screen.dart';

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

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

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
              backgroundColor: const Color(0xFFFF7722),
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
                            backgroundColor: const Color(0xFFFF7722),
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
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF7722))),
              error: (e, _) => Text('Error: $e'),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(userGroupsProvider);
    final invitesAsync = ref.watch(pendingInvitesProvider);

    return Scaffold(
      extendBodyBehindAppBar: true, // Allows background to flow under the app bar
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.85), // Slight frosted glass effect
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF7722).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.volunteer_activism_rounded, color: Color(0xFFFF6600), size: 26),
            ),
            const SizedBox(width: 12),
            const Text(
              'Chanda',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 26,
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
                child: const Icon(Icons.notifications_none_rounded, color: Colors.black87),
              ),
              onPressed: () => _showInvitesDialog(context, ref),
            ),
            orElse: () => IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.black87),
              onPressed: () => _showInvitesDialog(context, ref),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.black87),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Modern, subtle watermark background
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F2),
              image: DecorationImage(
                // Placeholder grocery/shopping image. Replace with your own asset later!
                image: const NetworkImage('https://images.unsplash.com/photo-1542838132-92c53300491e?q=80&w=1000&auto=format&fit=crop'),
                fit: BoxFit.cover,
                // The color filter heavily washes out the image so it doesn't clutter the UI
                colorFilter: ColorFilter.mode(
                  const Color(0xFFFFF8F2).withOpacity(0.92), 
                  BlendMode.lighten
                ),
              ),
            ),
          ),
          
          // Groups List
          SafeArea(
            child: groupsAsync.when(
              data: (groups) {
                if (groups.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.groups_outlined, size: 80, color: Colors.orange.shade200),
                        const SizedBox(height: 16),
                        const Text('No groups yet.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 8),
                        Text('Create one to start splitting bills.', style: TextStyle(fontSize: 16, color: Colors.grey.shade800)),
                      ],
                    )
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(top: 16, bottom: 100),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index].data() as Map<String, dynamic>;
                    
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF9933), Color(0xFFFF6600)], 
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF6600).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GroupDetailsScreen(
                                  groupId: group['groupId'],
                                  groupName: group['name'],
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.25),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.groups_rounded, color: Colors.white, size: 32),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    group['name'],
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 24),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF7722))),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFFF6600), 
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => _showCreateGroupDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Group', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}