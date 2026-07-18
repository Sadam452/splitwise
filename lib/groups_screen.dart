import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'group_details_screen.dart';
import 'auth_screen.dart';

// Stream of groups where the current user is in the 'members' array
final userGroupsProvider = StreamProvider<List<QueryDocumentSnapshot>>((ref) {
  // Watch the auth state so this resets when you switch accounts on the same device
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  
  if (user == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('groups')
      .where('members', arrayContains: user.uid)
      .snapshots()
      .map((snapshot) => snapshot.docs);
});

// Stream of pending invitations matching the user's email
final pendingInvitesProvider = StreamProvider<List<QueryDocumentSnapshot>>((ref) {
  // Watch the auth state here as well
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
        title: const Text('Create New Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Group Name (e.g., Flat 402)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: invitesController,
              decoration: const InputDecoration(
                labelText: 'Invite Emails (comma separated)',
                hintText: 'user1@test.com, user2@test.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              
              final user = FirebaseAuth.instance.currentUser!;
              final db = FirebaseFirestore.instance;
              
              // 1. Create the group
              final groupRef = db.collection('groups').doc();
              await groupRef.set({
                'groupId': groupRef.id,
                'name': nameController.text.trim(),
                'members': [user.uid],
                'createdBy': user.uid, 
              });

              // 2. Create the invitations
              //final emails = invitesController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
              final emails = invitesController.text.split(',')
    .map((e) => e.trim().toLowerCase()) // Forces exact lowercase match
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showInvitesDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pending Invitations'),
        content: Consumer(
          builder: (context, ref, child) {
            final invitesAsync = ref.watch(pendingInvitesProvider);
            
            return invitesAsync.when(
              data: (invites) {
                if (invites.isEmpty) return const Text('No pending invites.');
                
                return SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: invites.length,
                    itemBuilder: (context, index) {
                      final invite = invites[index].data() as Map<String, dynamic>;
                      final inviteId = invites[index].id;
                      
                      return ListTile(
                        title: Text(invite['groupName']),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            final user = FirebaseAuth.instance.currentUser!;
                            final db = FirebaseFirestore.instance;
                            final batch = db.batch();

                            // Batch write to update invite and add user to group
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
              loading: () => const Center(child: CircularProgressIndicator()),
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
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          // Dynamic invites icon (shows red dot if there are pending invites)
          invitesAsync.maybeWhen(
            data: (invites) => IconButton(
              icon: Badge(
                isLabelVisible: invites.isNotEmpty,
                label: Text(invites.length.toString()),
                child: const Icon(Icons.notifications),
              ),
              onPressed: () => _showInvitesDialog(context, ref),
            ),
            orElse: () => IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () => _showInvitesDialog(context, ref),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: groupsAsync.when(
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(child: Text('No groups yet. Create one to get started.'));
          }
return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index].data() as Map<String, dynamic>;
              
              return ListTile(
                title: Text(group['name']),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // Just the navigation action goes here
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
              );
              
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateGroupDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}