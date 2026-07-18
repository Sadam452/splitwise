import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class _EditableItem {
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  final List<String> splitBetween;

  _EditableItem({
    required this.nameCtrl,
    required this.qtyCtrl,
    required this.priceCtrl,
    required this.splitBetween,
  });
}

class EditBillDetailsScreen extends StatefulWidget {
  final String groupId;
  final String orderId;
  final Map<String, dynamic> orderData;

  const EditBillDetailsScreen({
    super.key,
    required this.groupId,
    required this.orderId,
    required this.orderData,
  });

  @override
  State<EditBillDetailsScreen> createState() => _EditBillDetailsScreenState();
}

class _EditBillDetailsScreenState extends State<EditBillDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _totalAmountController;
  
  final List<_EditableItem> _items = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.orderData['title'] ?? '');
    _totalAmountController = TextEditingController(text: widget.orderData['total_amount']?.toString() ?? '0.0');

    final itemsList = widget.orderData['items'] as List<dynamic>? ?? [];
    for (var item in itemsList) {
      _items.add(_EditableItem(
        nameCtrl: TextEditingController(text: item['name']?.toString() ?? ''),
        qtyCtrl: TextEditingController(text: item['quantity']?.toString() ?? '1'),
        priceCtrl: TextEditingController(text: item['price']?.toString() ?? '0.0'),
        splitBetween: List<String>.from(item['splitBetween'] ?? []),
      ));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _totalAmountController.dispose();
    for (var item in _items) {
      item.nameCtrl.dispose();
      item.qtyCtrl.dispose();
      item.priceCtrl.dispose();
    }
    super.dispose();
  }

  void _recalculateTotal() {
    double newTotal = 0;
    for (var item in _items) {
      newTotal += double.tryParse(item.priceCtrl.text.trim()) ?? 0.0;
    }
    setState(() {
      _totalAmountController.text = newTotal.toStringAsFixed(2);
    });
  }

  void _addNewItem() {
    setState(() {
      _items.add(_EditableItem(
        nameCtrl: TextEditingController(text: ''),
        qtyCtrl: TextEditingController(text: '1'),
        priceCtrl: TextEditingController(text: ''),
        splitBetween: [], 
      ));
    });
  }

  void _removeItem(int index) {
    setState(() {
      final item = _items.removeAt(index);
      item.nameCtrl.dispose();
      item.qtyCtrl.dispose();
      item.priceCtrl.dispose();
    });
    // Auto-update the total when an item is deleted
    _recalculateTotal();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must have at least one item in the bill.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      
      final List<Map<String, dynamic>> updatedItems = _items.map((item) {
        return {
          'name': item.nameCtrl.text.trim(),
          'quantity': int.tryParse(item.qtyCtrl.text.trim()) ?? 1,
          'price': double.tryParse(item.priceCtrl.text.trim()) ?? 0.0,
          'splitBetween': item.splitBetween,
        };
      }).toList();

      final updatedTotal = double.tryParse(_totalAmountController.text.trim()) ?? 0.0;

      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc(widget.orderId)
          .update({
        'title': _titleController.text.trim(),
        'total_amount': updatedTotal,
        'items': updatedItems,
        'updatedBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating bill: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Edit Bill Details', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveChanges,
            child: _isSaving 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('General Info', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Transaction Name',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a name' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _totalAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Total Amount',
                  prefixText: '₹ ',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Please enter an amount';
                  if (double.tryParse(val.trim()) == null) return 'Invalid number';
                  return null;
                },
              ),
              
              const SizedBox(height: 32),
              const Text('Individual Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 12),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
                      ],
                    ),
                    child: Column(
                      children: [
                        // Row 1: Item Name & Delete Button
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: item.nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Item Name',
                                  isDense: true,
                                ),
                                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _removeItem(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Row 2: Quantity and Price
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: TextFormField(
                                controller: item.qtyCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Quantity',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: item.priceCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (value) => _recalculateTotal(), // Auto-updates when typing!
                                decoration: const InputDecoration(
                                  labelText: 'Total Price',
                                  prefixText: '₹',
                                  isDense: true,
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Required';
                                  if (double.tryParse(val.trim()) == null) return 'Invalid';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _addNewItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Missing Item'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepPurple,
                    side: BorderSide(color: Colors.deepPurple.shade200),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}