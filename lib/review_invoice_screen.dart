import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReviewInvoiceScreen extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic> parsedData;
  final Map<String, dynamic> membersData;

  const ReviewInvoiceScreen({
    super.key,
    required this.groupId,
    required this.parsedData,
    required this.membersData,
  });

  @override
  State<ReviewInvoiceScreen> createState() => _ReviewInvoiceScreenState();
}

class _ReviewInvoiceScreenState extends State<ReviewInvoiceScreen> {
  late List<Map<String, dynamic>> _items;
  late TextEditingController _deliveryFeeController;
  late TextEditingController _otherFeesController;
  late TextEditingController _totalAmountController; // Replaced Discount Controller
  
  late String _selectedPayer;
  late List<String> _selectedSplitMembers;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.parsedData['items'] ?? []);
    
    _deliveryFeeController = TextEditingController(text: (widget.parsedData['delivery_fee'] ?? 0).toString());
    _otherFeesController = TextEditingController(text: (widget.parsedData['other_fees'] ?? 0).toString());
    
    // Set the initial total amount extracted by the AI
    _totalAmountController = TextEditingController(text: (widget.parsedData['total_amount'] ?? 0).toString());

    // Default to the current user as the payer
    final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    _selectedPayer = widget.membersData.containsKey(currentUserUid) 
        ? currentUserUid 
        : widget.membersData.keys.first;

    // Default to splitting among all group members
    _selectedSplitMembers = widget.membersData.keys.toList();
  }

  @override
  void dispose() {
    _deliveryFeeController.dispose();
    _otherFeesController.dispose();
    _totalAmountController.dispose();
    super.dispose();
  }

  String _getUserName(String uid) {
    final userData = widget.membersData[uid];
    if (userData == null) return 'Unknown';
    if (userData['firstName'] != null && userData['firstName'].toString().isNotEmpty) return userData['firstName'];
    return userData['email']?.toString().split('@').first ?? 'User';
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
                  children: widget.membersData.keys.map((uid) {
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

Future<void> _saveOrder() async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final orderRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc();

      final String orderTitle = widget.parsedData['title'] ?? 'Grocery Run';

      // 1. Fetch values
      double sumBeforeDiscount = _items.fold(0, (sum, item) => sum + (item['price'] ?? 0));
      double delivery = double.tryParse(_deliveryFeeController.text) ?? 0;
      double otherFees = double.tryParse(_otherFeesController.text) ?? 0;
      double finalTotalAmount = double.tryParse(_totalAmountController.text) ?? 0;

      List<Map<String, dynamic>> finalizedItems = [];
      double runningItemTotal = 0.0;
      
      // 3. Apply the implicit discount multiplier to each item
      for (int i = 0; i < _items.length; i++) {
        var item = _items[i];
        double originalPrice = (item['price'] ?? 0).toDouble();
        double discountedPrice = originalPrice;
        
        if (sumBeforeDiscount > 0) {
          discountedPrice = (finalTotalAmount / sumBeforeDiscount) * originalPrice;
        } else if (sumBeforeDiscount == 0) {
          discountedPrice = 0; 
        }

        // Round to 2 decimals immediately
        double roundedPrice = double.parse(discountedPrice.toStringAsFixed(2));

        // 1-paise fix: If it's the last item, give it the exact remaining balance
        if (i == _items.length - 1) {
           roundedPrice = double.parse((finalTotalAmount - runningItemTotal).toStringAsFixed(2));
        } else {
           runningItemTotal += roundedPrice;
        }

        finalizedItems.add({
          'name': item['name'],
          'quantity': item['quantity'],
          'price': roundedPrice,
          'splitBetween': List<String>.from(_selectedSplitMembers), 
        });
      }

      await orderRef.set({
        'orderId': orderRef.id,
        'title': orderTitle,
        'addedBy': _selectedPayer, 
        'updatedBy': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'items': finalizedItems,
        'delivery_fee': delivery,
        'other_fees': otherFees,
        'discount': 0, 
        'total_amount': finalTotalAmount,
        'status': 'open',
        'splitType': 'equal', // Explicitly label this as an equal split
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _editItemDialog(int index) {
    final item = _items[index];
    final nameCtrl = TextEditingController(text: item['name']);
    final priceCtrl = TextEditingController(text: item['price'].toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl, 
              decoration: InputDecoration(
                labelText: 'Item Name',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              )
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl, 
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Price (₹)',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              )
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _items[index]['name'] = nameCtrl.text;
                _items[index]['price'] = double.tryParse(priceCtrl.text) ?? 0;
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 16)),
          SizedBox(
            width: 100,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
              decoration: InputDecoration(
                prefixText: '₹',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Review Invoice', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.deepPurple),
            onPressed: () => setState(() => _items.add({'name': 'New Item', 'quantity': 1, 'price': 0.0})),
          )
        ],
      ),
      body: Column(
        children: [
          // Global Settings Header (Paid By & Split)
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Paid By:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedPayer,
                          items: widget.membersData.keys.map((uid) {
                            return DropdownMenuItem(
                              value: uid,
                              child: Text(_getUserName(uid)),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedPayer = val!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Split Between:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    TextButton.icon(
                      onPressed: _showSplitDialog, 
                      icon: const Icon(Icons.people_alt_outlined),
                      label: Text('${_selectedSplitMembers.length} Members'),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.deepPurple.shade50,
                        foregroundColor: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Items List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                return Dismissible(
                  key: Key(item['name'] + index.toString()),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => setState(() => _items.removeAt(index)),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                  child: InkWell(
                    onTap: () => _editItemDialog(index),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['name'], 
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '₹${item['price']}', 
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Fixed Bottom Summary Section
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5)),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSummaryRow('Delivery Fee', _deliveryFeeController),
                  _buildSummaryRow('Other Fees', _otherFeesController),
                  
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(),
                  ),
                  
                  // Editable Total Amount Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Amount', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: _totalAmountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.deepPurple),
                          decoration: const InputDecoration(
                            prefixText: '₹',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isSaving ? null : _saveOrder,
                      child: _isSaving 
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Confirm & Upload', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}