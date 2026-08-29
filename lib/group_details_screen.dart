import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'review_invoice_screen.dart';
import 'transaction_detail_screen.dart';
import 'add_manual_bill_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

// Stream for group's orders
final groupOrdersProvider =
    StreamProvider.family<List<QueryDocumentSnapshot>, String>((ref, groupId) {
      return FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('orders')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs);
    });

// Future to fetch member details (names, emails) to resolve UIDs
final groupMembersProvider =
    FutureProvider.family<Map<String, dynamic>, String>((
      ref,
      memberIdsString,
    ) async {
      if (memberIdsString.isEmpty) return {};

      final db = FirebaseFirestore.instance;
      Map<String, dynamic> membersData = {};

      final memberIds = memberIdsString.split(',');

      for (String uid in memberIds) {
        final doc = await db.collection('users').doc(uid).get();
        membersData[uid] = doc.data() ?? {};
      }
      return membersData;
    });

// Stream for the current group details to get the member list
final currentGroupProvider = StreamProvider.family<DocumentSnapshot, String>((
  ref,
  groupId,
) {
  return FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .snapshots();
});

class GroupDetailsScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;

  const GroupDetailsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  ConsumerState<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends ConsumerState<GroupDetailsScreen> {
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();
  String? _groupAdminId;
  @override
  void initState() {
    super.initState();
    _fetchGroupAdmin();
    // ... any other initState code you already have ...
  }
  Future<void> _settleDebt(String creditorUid, String creditorName, double amount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settle Up'),
        content: Text(
          'Are you sure you have settled ₹${amount.toStringAsFixed(2)} with $creditorName via UPI/Cash/Bank Transfer?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green, 
              foregroundColor: Colors.white
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Settled'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
      
      try {
        final orderRef = FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('orders')
            .doc();

        // We record this as a transaction where the current user pays the exact amount 
        // completely on behalf of the creditor. This perfectly cancels out the debt math.
        await orderRef.set({
          'orderId': orderRef.id,
          'title': '💸 Settlement: to $creditorName',
          'addedBy': currentUserUid,
          'updatedBy': currentUserUid,
          'timestamp': FieldValue.serverTimestamp(),
          'items': [
            {
              'name': 'Settlement',
              'quantity': 1,
              'price': amount,
              'splitBetween': [creditorUid], 
            }
          ],
          'delivery_fee': 0.0,
          'other_fees': 0.0,
          'discount': 0.0,
          'total_amount': amount,
          'status': 'open',
          'splitType': 'equal',
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Debt marked as settled!'))
          );
        }
      } catch (e) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error settling debt: $e'))
           );
        }
      }
    }
  }

  Future<void> _fetchGroupAdmin() async {
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .get();
    if (mounted) {
      setState(() {
        // Fallback to the first member for groups created before we added 'createdBy'
        _groupAdminId =
            doc.data()?['createdBy'] ??
            (doc.data()?['members'] as List?)?.first;
      });
    }
  }

  void _showInviteDialog() {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Member'),
        content: TextField(
          controller: emailController,
          decoration: const InputDecoration(
            labelText: 'Email Address',
            hintText: 'friend@example.com',
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim().toLowerCase();
              if (email.isEmpty) return;

              try {
                await FirebaseFirestore.instance.collection('invitations').add({
                  'groupId': widget.groupId,
                  'groupName': widget
                      .groupName, // Make sure groupName is passed to your StatefulWidget
                  'inviteeEmail': email,
                  'status': 'pending',
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invitation sent!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Send Invite'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text(
          'Are you sure you want to permanently delete this group? All bills and balances will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Deletes the group document. (Note: standard Firestore behavior leaves subcollections intact in the database,
        // but the group will be instantly removed from everyone's UI).
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .delete();

        if (mounted) {
          Navigator.pop(context); // Go back to the main groups list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting group: $e')));
        }
      }
    }
  }

Future<void> _pickImage(ImageSource source) async {
    // Navigator.pop is removed here because we handle it in the button's onTap
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 50,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    await _processInvoiceData(bytes, 'image/jpeg');
  }

// Future<void> _pickPdf() async {
//     // Navigator.pop removed here because we handle it in the button's onTap
//     final FilePickerResult? result = await FilePicker.pickFiles(
//       type: FileType.custom,
//       allowedExtensions: ['pdf'],
//     );
//     if (result == null || result.files.single.path == null) return;
//     final bytes = await File(result.files.single.path!).readAsBytes();
//     await _processInvoiceData(bytes, 'application/pdf');
//   }
Future<void> _pickPdf() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true, // Tell the picker to fetch the raw bytes directly
      );
      
      if (result == null) return; // User canceled the picker

      // Use the direct bytes if available, fallback to reading the path just in case
      final bytes = result.files.single.bytes ?? await File(result.files.single.path!).readAsBytes();
      
      await _processInvoiceData(bytes, 'application/pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading PDF: $e')),
        );
      }
    }
  }

  Future<void> _processInvoiceData(List<int> bytes, String mimeType) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final promptText = "You are a highly accurate receipt parsing assistant. Your task is to extract structured data from the provided Indian grocery invoice. "
        "1. Generate a short, meaningful 'title' for this order based on the vendor or items (e.g., 'Zepto Weekend Run', 'Instamart Snacks'). "
        "2. Extract all individual ordered items, their quantities, and their total prices. "
        "3. Extract the standard delivery fee and any applied discounts. "
        "4. Look carefully for any additional overhead charges like handling fees, rain fees, surge pricing, platform fees, or small order fees. "
        "Sum all of these miscellaneous charges together into a single 'other_fees' value. "
        "Do not guess; if a numeric value is not clearly visible, default to 0. "
        "Return the output STRICTLY as a valid JSON object matching this schema: "
        "{ \"title\": \"string\", \"items\": [ { \"name\": \"string\", \"quantity\": 1, \"price\": 0.0 } ], \"delivery_fee\": 0.0, \"other_fees\": 0.0, \"discount\": 0.0, \"total_amount\": 0.0 }";

    try {
      final docSnapshot = await FirebaseFirestore.instance.collection('app_config').doc('secrets').get();
      final geminiApiKey = docSnapshot.data()?['gemini_api_key'];
      final groqApiKey = docSnapshot.data()?['groq_api_key']; 
      
      if (geminiApiKey == null || groqApiKey == null) throw Exception("API Keys missing");

      String? responseText;
      bool groqAttemptedAndFailed = false;

      // --- ATTEMPT 1: GROQ (Primary for both Images and PDFs) ---
      try {
        List<Map<String, dynamic>> contentList = [];
        
        if (mimeType == 'application/pdf') {
          // DIGITAL PDF: Extract text locally and pass it to Groq as a simple text prompt
          final PdfDocument document = PdfDocument(inputBytes: bytes);
          final String extractedText = PdfTextExtractor(document).extractText();
          document.dispose();

          if (extractedText.trim().isEmpty) {
             throw Exception("Could not extract text from PDF (it might be a scanned image).");
          }

          contentList.add({
            "type": "text", 
            "text": promptText + "\n\nHere is the extracted invoice text:\n$extractedText\n\nPlease pull out relevant information as a JSON object in JSON format."
          });
        } else {
          // IMAGE: Process using Vision
          final base64Image = base64Encode(bytes);
          contentList.add({"type": "text", "text": promptText + "\nPlease pull out relevant information as a JSON object in JSON format."});
          contentList.add({
            "type": "image_url",
            "image_url": {"url": "data:$mimeType;base64,$base64Image"}
          });
        }
        
        final groqResponse = await http.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $groqApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            "model": "qwen/qwen3.8-27b", 
            "messages": [
              {
                "role": "user",
                "content": contentList 
              }
            ],
            "response_format": {"type": "json_object"},
            "temperature": 0.1, 
            "max_tokens": 2048, 
          }),
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException('Groq is taking too long.'),
        );
        
        if (groqResponse.statusCode == 200) {
          final data = jsonDecode(groqResponse.body);
          responseText = data['choices'][0]['message']['content'];
        } else {
          throw Exception("Groq Failed: ${groqResponse.body}");
        }
        
      } catch (groqError) {
        debugPrint("Groq Failed or Timed Out ($groqError). Falling back to Gemini...");
        groqAttemptedAndFailed = true;
      }

      // --- ATTEMPT 2: GEMINI (Fallback) ---
      if (responseText == null) {
        
        if (groqAttemptedAndFailed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The parsing is taking longer than usual, please wait as we try again...'),
              duration: Duration(seconds: 4),
              backgroundColor: Colors.deepPurple, 
            ),
          );
        }

        final model = GenerativeModel(
          model: 'gemini-flash-latest',
          apiKey: geminiApiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: Schema.object(
              properties: {
                'title': Schema.string(),
                'items': Schema.array(
                  items: Schema.object(
                    properties: {
                      'name': Schema.string(),
                      'quantity': Schema.number(),
                      'price': Schema.number(),
                    },
                    requiredProperties: ['name', 'quantity', 'price'],
                  ),
                ),
                'delivery_fee': Schema.number(),
                'other_fees': Schema.number(),
                'discount': Schema.number(),
                'total_amount': Schema.number(),
              },
              requiredProperties: ['title', 'items', 'total_amount'],
            ),
          ),
        );

        final documentPart = DataPart(mimeType, Uint8List.fromList(bytes));
        
        try {
          final response = await model.generateContent([
            Content.multi([TextPart(promptText), documentPart]),
          ]).timeout(
            const Duration(seconds: 12), 
            onTimeout: () => throw TimeoutException('Gemini is taking too long.'),
          );
          
          responseText = response.text;
        } catch (geminiError) {
          throw Exception("Failed to parse invoice. Please try again later. [Error Code: GeGr-002]");
        }
      }

      // --- PARSE AND NAVIGATE ---
      if (responseText != null) {
        final Map<String, dynamic> receiptData = jsonDecode(responseText);

        final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get();
        final membersList = List<String>.from(groupDoc['members'] ?? []);
        Map<String, dynamic> fetchedMembersData = {};
        for (String uid in membersList) {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          fetchedMembersData[uid] = userDoc.data() ?? {};
        }

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReviewInvoiceScreen(
                groupId: widget.groupId,
                parsedData: receiptData,
                membersData: fetchedMembersData, 
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  
  String _getUserName(String uid, Map<String, dynamic> membersData) {
    final userData = membersData[uid];
    if (userData == null) return 'Unknown';
    if (userData['firstName'] != null &&
        userData['firstName'].toString().isNotEmpty) {
      return userData['firstName'];
    }
    final email = userData['email']?.toString() ?? 'User';
    return email.split('@').first;
  }

  /// Calculates net simplified balances across all orders in the group
  Map<String, Map<String, double>> _calculateGroupDebts(
    List<QueryDocumentSnapshot> orderDocs,
    List<dynamic> memberIds,
  ) {
    Map<String, Map<String, double>> grossDebts = {
      for (var uid in memberIds)
        uid: {
          for (var other in memberIds)
            if (uid != other) other: 0.0,
        },
    };

    for (var doc in orderDocs) {
      final orderData = doc.data() as Map<String, dynamic>;

      // Skip this order entirely if it was deleted
      if (orderData['status'] == 'deleted') continue;

      final payer = orderData['addedBy'];
      if (!memberIds.contains(payer)) continue;

      final items = orderData['items'] as List<dynamic>? ?? [];
      Map<String, double> orderSplits = {for (var uid in memberIds) uid: 0.0};

      // Calculate splits purely based on the already-scaled items
      for (var item in items) {
        List<String> splitBetween = List<String>.from(
          item['splitBetween'] ?? memberIds,
        );
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

      for (var uid in memberIds) {
        if (uid != payer) {
          grossDebts[uid]![payer] =
              (grossDebts[uid]![payer] ?? 0.0) + orderSplits[uid]!;
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

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(currentGroupProvider(widget.groupId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
appBar: AppBar(
          title: Text(widget.groupName, style: const TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.deepPurple),
              onSelected: (value) {
                if (value == 'invite') _showInviteDialog();
                if (value == 'delete') _deleteGroup();
              },
              itemBuilder: (context) {
                final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
                final isOwner = currentUserUid != null && currentUserUid == _groupAdminId;
                
                return [
                  const PopupMenuItem(
                    value: 'invite', 
                    child: Row(
                      children: [
                        Icon(Icons.person_add_outlined, size: 20, color: Colors.black87),
                        SizedBox(width: 12),
                        Text('Invite Member'),
                      ],
                    )
                  ),
                  if (isOwner)
                    const PopupMenuItem(
                      value: 'delete', 
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Delete Group', style: TextStyle(color: Colors.red)),
                        ],
                      )
                    ),
                ];
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepPurple,
            tabs: [
              Tab(text: 'Transactions'),
              Tab(text: 'Members & Balances'),
            ],
          ),
        ),
        body: groupAsync.when(
          data: (groupDoc) {
            final membersList = groupDoc['members'] as List<dynamic>? ?? [];
            final membersString = membersList.join(',');
            final membersDataAsync = ref.watch(
              groupMembersProvider(membersString),
            );

            return membersDataAsync.when(
              data: (membersData) {
                return TabBarView(
                  children: [
                    _buildTransactionsTab(membersData),
                    _buildBalancesTab(membersList, membersData),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading members: $e')),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading group: $e')),
        ),
floatingActionButton: FloatingActionButton.extended(
        // Dim the button slightly while processing to indicate it's busy
        backgroundColor: _isProcessing ? Colors.deepPurple.shade300 : Colors.deepPurple,
        foregroundColor: Colors.white,
        
        // Swap the icon for a loading spinner when active
        icon: _isProcessing 
            ? const SizedBox(
                width: 20, 
                height: 20, 
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
              )
            : const Icon(Icons.add),
            
        // Change the text to give the user clear feedback
        label: Text(_isProcessing ? 'Analyzing...' : 'Add Bill'),
        
        // Disable the button completely while processing to prevent double-taps
        onPressed: _isProcessing 
            ? null 
            : () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  builder: (BuildContext bottomSheetContext) {
                    return SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'How would you like to add the bill?', 
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                            ),
                            const SizedBox(height: 20),
                            
                            // AI Scan - Camera
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue.shade50,
                                child: const Icon(Icons.camera_alt_outlined, color: Colors.blue),
                              ),
                              title: const Text('Take Photo (AI Scan)', style: TextStyle(fontWeight: FontWeight.w600)),
                              onTap: () {
                                Navigator.pop(bottomSheetContext);
                                _pickImage(ImageSource.camera);
                              },
                            ),
                            const Divider(height: 8),

                            // AI Scan - Gallery
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.purple.shade50,
                                child: const Icon(Icons.image_outlined, color: Colors.purple),
                              ),
                              title: const Text('Upload from Gallery (AI Scan)', style: TextStyle(fontWeight: FontWeight.w600)),
                              onTap: () {
                                Navigator.pop(bottomSheetContext);
                                _pickImage(ImageSource.gallery);
                              },
                            ),
                            const Divider(height: 8),

                            // AI Scan - PDF
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.red.shade50,
                                child: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
                              ),
                              title: const Text('Upload PDF (AI Scan)', style: TextStyle(fontWeight: FontWeight.w600)),
                              onTap: () {
                                Navigator.pop(bottomSheetContext);
                                _pickPdf();
                              },
                            ),
                            const Divider(height: 8),

                            // Manual Entry
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.deepPurple.shade50,
                                child: const Icon(Icons.edit_note_outlined, color: Colors.deepPurple),
                              ),
                              title: const Text('Add Manually', style: TextStyle(fontWeight: FontWeight.w600)),
                              onTap: () {
                                Navigator.pop(bottomSheetContext);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AddManualBillScreen(
                                      groupId: widget.groupId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
      ),
      ),
    );
  }

Widget _buildTransactionsTab(Map<String, dynamic> membersData) {
    final ordersAsync = ref.watch(groupOrdersProvider(widget.groupId));

    return ordersAsync.when(
      data: (orders) {
        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('No bills yet.', style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text('Tap the + button below to add one.', style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100, top: 12),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final orderDoc = orders[index];
            final order = orderDoc.data() as Map<String, dynamic>;

            final List<String> reviewedBy = List<String>.from(order['reviewedBy'] ?? []);
final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
final hasReviewed = currentUserUid != null && reviewedBy.contains(currentUserUid);

            final date = (order['timestamp'] as Timestamp?)?.toDate();
            final dateString = date != null ? "${date.day}/${date.month}/${date.year}" : "";

            final title = order['title'] ?? 'Untitled Order';
            final totalAmount = order['total_amount'] ?? 0;
            final addedByName = _getUserName(order['addedBy'], membersData);

            final isDeleted = order['status'] == 'deleted';
            final deletedByUid = order['deletedBy'];
            final deletedByName = deletedByUid != null ? _getUserName(deletedByUid, membersData) : 'Unknown';

            final isSettlement = title.toString().startsWith('💸 Settlement');

            String displayTitle = title;
            IconData leadingIcon = Icons.receipt_long_rounded;
            Color iconBgColor = Colors.deepPurple.shade50;
            Color iconColor = Colors.deepPurple;
            Color amountColor = Colors.black87;

            // UI adjustments based on transaction type
            if (isDeleted) {
              iconBgColor = Colors.grey.shade100;
              iconColor = Colors.grey.shade400;
              amountColor = Colors.grey.shade400;
            } else if (isSettlement) {
              leadingIcon = Icons.handshake_rounded;
              iconBgColor = Colors.blue.shade50;
              iconColor = Colors.blue.shade700;
              amountColor = Colors.blue.shade700;
              
              try {
                final creditorUid = order['items'][0]['splitBetween'][0];
                final creditorName = _getUserName(creditorUid, membersData);
                displayTitle = 'Settled with $creditorName'; // Cleaner title for the UI
              } catch (_) {}
            }

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TransactionDetailScreen(
                          groupId: widget.groupId,
                          orderId: orderDoc.id,
                          orderData: order,
                          membersData: membersData,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Modern Circular Icon
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
                          child: Icon(leadingIcon, color: iconColor, size: 24),
                        ),
                        const SizedBox(width: 16),
                        
                        // Details Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Fetch the reviewed array and check if the current user has seen it


// Render the title alongside the indicator
// Render the title alongside the indicator
Row(
  children: [
    Flexible(
      child: Text(
        displayTitle,
        style: TextStyle(
          fontWeight: hasReviewed ? FontWeight.w600 : FontWeight.w800, // Bolder if unread
          fontSize: 16,
          color: isDeleted ? Colors.grey.shade400 : Colors.black87,
          decoration: isDeleted ? TextDecoration.lineThrough : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    const SizedBox(width: 8),
    if (!hasReviewed && !isDeleted)
      Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
      )
    else if (hasReviewed && !isDeleted)
      const Icon(Icons.done_all_rounded, size: 16, color: Colors.green)
  ],
),
                              const SizedBox(height: 4),
                              Text(
                                isSettlement ? '$addedByName paid • $dateString' : 'Added by $addedByName • $dateString',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                              ),
                              if (isDeleted)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('Deleted by $deletedByName', style: TextStyle(color: Colors.red.shade300, fontSize: 12, fontStyle: FontStyle.italic)),
                                )
                            ],
                          ),
                        ),
                        
                        // Amount
                        Text(
                          '₹$totalAmount',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: amountColor,
                            decoration: isDeleted ? TextDecoration.lineThrough : null,
                          ),
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

Widget _buildBalancesTab(
    List<dynamic> membersList,
    Map<String, dynamic> membersData,
  ) {
    final ordersAsync = ref.watch(groupOrdersProvider(widget.groupId));
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid; 

    return ordersAsync.when(
      data: (orders) {
        final netDebts = _calculateGroupDebts(orders, membersList);

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80, top: 16),
          itemCount: membersList.length,
          itemBuilder: (context, index) {
            final uid = membersList[index];
            final name = _getUserName(uid, membersData);
            final email = membersData[uid]?['email'] ?? '';
            
            // Extract photo URL (checking common Firestore keys for Google Auth images)
            final photoUrl = membersData[uid]?['photoURL'] ?? 
                             membersData[uid]?['photoUrl'] ?? 
                             membersData[uid]?['profilePic'];
                             
            final isCurrentUser = uid == currentUserUid;

            double totalOwed = 0;
            Map<String, double> owesTo = {};
            netDebts[uid]?.forEach((creditorUid, amount) {
              if (amount > 0) {
                totalOwed += amount;
                owesTo[creditorUid] = amount;
              }
            });

            double totalReceivable = 0;
            Map<String, double> receivableFrom = {};
            for (var debtorUid in membersList) {
              if (debtorUid != uid) {
                double amount = netDebts[debtorUid]?[uid] ?? 0;
                if (amount > 0) {
                  totalReceivable += amount;
                  receivableFrom[debtorUid] = amount;
                }
              }
            }

            return Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  
                  // NEW: Profile Picture Avatar
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurple.shade100,
                    backgroundImage: (photoUrl != null && photoUrl.toString().isNotEmpty)
                        ? NetworkImage(photoUrl.toString())
                        : null,
                    child: (photoUrl == null || photoUrl.toString().isEmpty)
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.deepPurple,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    email,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (totalOwed > 0)
                        Text(
                          'Owes ₹${totalOwed.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.red,
                          ),
                        ),
                      if (totalReceivable > 0)
                        Text(
                          'Gets back ₹${totalReceivable.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.green,
                          ),
                        ),
                      if (totalOwed == 0 && totalReceivable == 0)
                        const Text(
                          'Settled up',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                  children: [
                    if (owesTo.isEmpty && receivableFrom.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'No outstanding balances.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    if (owesTo.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 8,
                          bottom: 4,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Owes to:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      ...owesTo.entries.map(
                        (e) {
                          final creditorUid = e.key;
                          final amount = e.value;
                          final creditorName = _getUserName(creditorUid, membersData);
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    creditorName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  '₹${amount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (isCurrentUser) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    height: 32,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        foregroundColor: Colors.green,
                                        side: const BorderSide(color: Colors.green),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _settleDebt(creditorUid, creditorName, amount),
                                      child: const Text('Settle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ]
                              ],
                            ),
                          );
                        }
                      ),
                    ],
                    if (receivableFrom.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 12,
                          bottom: 4,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Owed by:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      ...receivableFrom.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _getUserName(e.key, membersData),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '₹${e.value.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading balances: $e')),
    );
  }
}
