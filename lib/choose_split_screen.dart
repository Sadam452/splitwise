import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChooseSplitScreen extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic> draftData;
  final Map<String, dynamic> membersData;

  const ChooseSplitScreen({
    super.key,
    required this.groupId,
    required this.draftData,
    required this.membersData,
  });

  @override
  State<ChooseSplitScreen> createState() => _ChooseSplitScreenState();
}

class _ChooseSplitScreenState extends State<ChooseSplitScreen> {
  bool _isSaving = false;
  
  // Track which mode we are in. Default is true (Equal)
  bool _isEqualMode = true; 
  
  // Controllers for the unequal split amounts
  final Map<String, TextEditingController> _unequalControllers = {};
  
  late double _totalAmount;
  late List<String> _splitMembers;

  @override
  void initState() {
    super.initState();
    _totalAmount = (widget.draftData['total_amount'] ?? 0).toDouble();
    _splitMembers = List<String>.from(widget.draftData['selectedSplitMembers'] ?? []);
    
    // Initialize controllers for the unequal tab
    for (String uid in _splitMembers) {
      _unequalControllers[uid] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (var ctrl in _unequalControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String _getUserName(String uid) {
    final userData = widget.membersData[uid];
    if (userData == null) return 'Unknown';
    if (userData['firstName'] != null && userData['firstName'].toString().isNotEmpty) {
      return userData['firstName'];
    }
    return userData['email']?.toString().split('@').first ?? 'User';
  }

  double _getEnteredTotal() {
    double total = 0;
    for (var ctrl in _unequalControllers.values) {
      total += double.tryParse(ctrl.text.trim()) ?? 0.0;
    }
    return total;
  }

  Future<void> _saveFinalBill() async {
    // Validation for Unequal splits
    if (!_isEqualMode) {
      double enteredTotal = _getEnteredTotal();
      // Using a small threshold (0.01) to avoid strict floating-point exactness issues
      if ((enteredTotal - _totalAmount).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Amounts must add up to ₹${_totalAmount.toStringAsFixed(2)}. Currently ₹${enteredTotal.toStringAsFixed(2)}.'
            )
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    
    try {
      final orderRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('orders')
          .doc();

      // Build exact amounts map if in unequal mode
      Map<String, double>? exactAmounts;
      if (!_isEqualMode) {
        exactAmounts = {};
        for (String uid in _splitMembers) {
          exactAmounts[uid] = double.tryParse(_unequalControllers[uid]!.text.trim()) ?? 0.0;
        }
      }

      // Clone draft data and remove the temporary 'selectedSplitMembers' field
      final Map<String, dynamic> finalDataToSave = Map.from(widget.draftData);
      finalDataToSave.remove('selectedSplitMembers');

      await orderRef.set({
        ...finalDataToSave,
        'orderId': orderRef.id,
        'splitType': _isEqualMode ? 'equal' : 'unequal',
        'exactAmounts': exactAmounts, // Will be null if equal, which is fine
        'status': 'open',
      });

      if (mounted) {
        // Pop twice to get back to the group details screen
        Navigator.pop(context); 
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double enteredTotal = _getEnteredTotal();
    double remaining = _totalAmount - enteredTotal;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Choose Split', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          // Total Amount Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              children: [
                const Text('Total Amount', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '₹${_totalAmount.toStringAsFixed(2)}', 
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.deepPurple)
                ),
              ],
            ),
          ),
          
          // Custom Toggle Buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _isEqualMode ? Colors.deepPurple : Colors.grey.shade200,
                      foregroundColor: _isEqualMode ? Colors.white : Colors.black87,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
                      ),
                    ),
                    onPressed: () => setState(() => _isEqualMode = true),
                    child: const Text('Equally'),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: !_isEqualMode ? Colors.deepPurple : Colors.grey.shade200,
                      foregroundColor: !_isEqualMode ? Colors.white : Colors.black87,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
                      ),
                    ),
                    onPressed: () => setState(() => _isEqualMode = false),
                    child: const Text('Unequally'),
                  ),
                ),
              ],
            ),
          ),

          // Main Content Area
          Expanded(
            child: _isEqualMode ? _buildEqualView() : _buildUnequalView(),
          ),

          // Remaining tracker for unequal mode
          if (!_isEqualMode)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: remaining == 0 ? Colors.green.shade50 : Colors.orange.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    remaining == 0 
                        ? 'Amount split perfectly!' 
                        : '${remaining > 0 ? "₹${remaining.toStringAsFixed(2)} left" : "Over by ₹${remaining.abs().toStringAsFixed(2)}"}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: remaining == 0 ? Colors.green.shade700 : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),

          // Save Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSaving ? null : _saveFinalBill,
                  child: _isSaving 
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save Transaction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEqualView() {
    double perPerson = _totalAmount / _splitMembers.length;
    
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _splitMembers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        String uid = _splitMembers[index];
        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: CircleAvatar(
            backgroundColor: Colors.deepPurple.shade50,
            child: Text(_getUserName(uid)[0].toUpperCase(), style: const TextStyle(color: Colors.deepPurple)),
          ),
          title: Text(_getUserName(uid), style: const TextStyle(fontWeight: FontWeight.w500)),
          trailing: Text('₹${perPerson.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        );
      },
    );
  }

  Widget _buildUnequalView() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _splitMembers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        String uid = _splitMembers[index];
        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: CircleAvatar(
            backgroundColor: Colors.deepPurple.shade50,
            child: Text(_getUserName(uid)[0].toUpperCase(), style: const TextStyle(color: Colors.deepPurple)),
          ),
          title: Text(_getUserName(uid), style: const TextStyle(fontWeight: FontWeight.w500)),
          trailing: SizedBox(
            width: 100,
            child: TextField(
              controller: _unequalControllers[uid],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              onChanged: (val) => setState(() {}), // Trigger rebuild to update "remaining" tracker
              decoration: InputDecoration(
                prefixText: '₹ ',
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
        );
      },
    );
  }
}