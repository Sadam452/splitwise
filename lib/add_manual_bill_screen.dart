import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'choose_split_screen.dart';

class AddManualBillScreen extends StatefulWidget {
  final String groupId;

  const AddManualBillScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<AddManualBillScreen> createState() => _AddManualBillScreenState();
}

class _AddManualBillScreenState extends State<AddManualBillScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  String? _selectedPayer;
  List<String> _selectedSplitMembers = [];
  Map<String, dynamic> _membersData = {};
  
  bool _isLoadingMembers = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchGroupMembers();
  }

  Future<void> _fetchGroupMembers() async {
    try {
      final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get();
      final List<dynamic> memberIds = groupDoc.data()?['members'] ?? [];

      Map<String, dynamic> data = {};
      for (String uid in memberIds) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (userDoc.exists) {
          data[uid] = userDoc.data();
        }
      }

      if (mounted) {
        setState(() {
          _membersData = data;
          _selectedSplitMembers = data.keys.toList();
          
          final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
          _selectedPayer = data.containsKey(currentUserUid) ? currentUserUid : data.keys.first;
          
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading members: $e')));
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _getUserName(String uid) {
    final userData = _membersData[uid];
    if (userData == null) return 'Unknown';
    if (userData['firstName'] != null && userData['firstName'].toString().isNotEmpty) return userData['firstName'];
    return userData['email']?.toString().split('@').first ?? 'User';
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  void _showSplitDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Split Between'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _membersData.keys.map((uid) {
                    return CheckboxListTile(
                      title: Text(_getUserName(uid)),
                      value: _selectedSplitMembers.contains(uid),
                      onChanged: (bool? checked) {
                        setDialogState(() {
                          if (checked == true) {
                            _selectedSplitMembers.add(uid);
                          } else {
                            if (_selectedSplitMembers.length > 1) {
                              _selectedSplitMembers.remove(uid);
                            }
                          }
                        });
                        setState(() {}); 
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), 
                  child: const Text('Done')
                ),
              ],
            );
          },
        );
      }
    );
  }

void _saveManualBill() {
    if (!_formKey.currentState!.validate() || _selectedPayer == null) return;
    
    final user = FirebaseAuth.instance.currentUser!;
    final String billTitle = _titleController.text.trim();
    final double totalAmount = double.parse(_amountController.text.trim());

    final List<Map<String, dynamic>> finalizedItems = [
      {
        'name': billTitle,
        'quantity': 1,
        'price': totalAmount,
        'splitBetween': List<String>.from(_selectedSplitMembers),
      }
    ];

    final draftData = {
      'title': billTitle,
      'addedBy': _selectedPayer, 
      'updatedBy': user.uid,
      'timestamp': Timestamp.fromDate(_selectedDate),
      'items': finalizedItems,
      'delivery_fee': 0.0,
      'other_fees': 0.0,
      'discount': 0.0,
      'total_amount': totalAmount,
      'selectedSplitMembers': _selectedSplitMembers, // Passed so the next screen knows who to show
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChooseSplitScreen(
          groupId: widget.groupId,
          draftData: draftData,
          membersData: _membersData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Add Bill Manually', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _isLoadingMembers 
        ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
        : Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Transaction Info', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Name of Transaction',
                      hintText: 'e.g., Wifi Bill, Groceries, Dinner',
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a name' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Total Amount',
                      prefixText: '₹ ',
                    ),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Please enter an amount';
                      if (double.tryParse(val.trim()) == null || double.parse(val.trim()) <= 0) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  const Text('Details & Splitting', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 8),

                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.calendar_today, color: Colors.deepPurple),
                      title: const Text('Date of Transaction', style: TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text('${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
                      trailing: const Icon(Icons.arrow_drop_down),
                      onTap: () => _selectDate(context),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.account_balance_wallet_outlined, color: Colors.deepPurple),
                              SizedBox(width: 16),
                              Text('Paid By', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                            ],
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedPayer,
                              items: _membersData.keys.map((uid) {
                                return DropdownMenuItem(
                                  value: uid,
                                  child: Text(_getUserName(uid)),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedPayer = val!),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.people_alt_outlined, color: Colors.deepPurple),
                      title: const Text('Split Between', style: TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text('${_selectedSplitMembers.length} Members selected'),
                      trailing: TextButton(
                        onPressed: _showSplitDialog,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.deepPurple.shade50,
                          foregroundColor: Colors.deepPurple,
                        ),
                        child: const Text('Change'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isSaving ? null : _saveManualBill,
                      child: _isSaving 
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Split Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}