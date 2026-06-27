import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/database/database_helper.dart';

class LabourPaymentScreen extends StatefulWidget {
  const LabourPaymentScreen({super.key});

  @override
  State<LabourPaymentScreen> createState() => _LabourPaymentScreenState();
}

class _LabourPaymentScreenState extends State<LabourPaymentScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _labourList = [];
  int? _selectedLabourId;
  Map<String, dynamic> _getSelectedLabour() => _labourList.firstWhere((l) => l['id'] == _selectedLabourId, orElse: () => {});
  List<Map<String, dynamic>> _paymentHistory = [];

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _referenceCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  String _paymentMode = 'Cash';
  bool _isSaving = false;
  bool _isLoading = false;

  double _totalEarned = 0.0;
  double _totalPaid = 0.0;
  double _balance = 0.0;

  final List<String> _paymentModes = ['Cash', 'UPI', 'Cheque', 'Bank Transfer'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateCtrl.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _loadAllLabour();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _dateCtrl.dispose();
    _referenceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllLabour() async {
    final db = await _db.database;
    final rows =
        await db.query('labour', orderBy: 'name ASC');
    setState(() => _labourList = rows);
  }

  Future<void> _loadLabourSummary(int labourId, String labourType) async {
    setState(() => _isLoading = true);
    final db = await _db.database;

    double earned = 0.0;
    if (labourType == 'Daily Wage') {
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(earned_amount), 0) as total FROM labour_attendance WHERE labour_id = ?',
        [labourId],
      );
      earned = (rows.first['total'] as num?)?.toDouble() ?? 0.0;
    } else {
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(lpi.quantity_made * lpi.rate_per_unit), 0) as total '
        'FROM labour_production lp '
        'JOIN labour_production_items lpi ON lpi.production_id = lp.id '
        "WHERE lp.labour_id = ? AND lp.status != 'Cancelled'",
        [labourId],
      );
      earned = (rows.first['total'] as num?)?.toDouble() ?? 0.0;
    }

    final paidRows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM labour_payments WHERE labour_id = ?',
      [labourId],
    );
    final double paid = (paidRows.first['total'] as num?)?.toDouble() ?? 0.0;

    final history = await db.query(
      'labour_payments',
      where: 'labour_id = ?',
      whereArgs: [labourId],
      orderBy: 'payment_date DESC',
    );

    setState(() {
      _totalEarned = earned;
      _totalPaid = paid;
      _balance = (earned - paid) < 0 ? 0.0 : (earned - paid);
      _paymentHistory = history;
      _isLoading = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) {
      _dateCtrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _savePayment() async {
    if (_selectedLabourId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a labour'),
            backgroundColor: Colors.red),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final db = await _db.database;
      final int labourId = _selectedLabourId!;
      final double amount = double.parse(_amountCtrl.text.trim());
      final String date = _dateCtrl.text.trim();

      // Save payment + auto-create expense in one transaction
      await db.transaction((txn) async {
        final int paymentId = await txn.insert('labour_payments', {
          'labour_id': labourId,
          'amount': amount,
          'payment_date': date,
          'payment_mode': _paymentMode,
          'reference_number': _referenceCtrl.text.trim().isEmpty
              ? null
              : _referenceCtrl.text.trim(),
          'notes':
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        });

        // Auto-create expense (Rule: Labour Salary auto expense)
        await txn.insert('expenses', {
          'expense_date': date,
          'category': 'Labour Salary',
          'amount': amount,
          'note': 'Auto — ${_getSelectedLabour()['name']}',
          'is_auto': 1,
          'labour_payment_id': paymentId,
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Payment saved'),
              backgroundColor: Colors.green),
        );
        _amountCtrl.clear();
        _referenceCtrl.clear();
        _notesCtrl.clear();
        _paymentMode = 'Cash';
        _loadLabourSummary(
            labourId, _getSelectedLabour()['labour_type'] as String);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to save. Please try again.'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatDate(String raw) {
    try {
      final parts = raw.split('-');
      final months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${parts[2]} ${months[int.parse(parts[1])]} ${parts[0]}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Labour Payment'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Labour selector
            DropdownButtonFormField<int>(
              value: _selectedLabourId,
              decoration: const InputDecoration(
                labelText: 'Select Labour *',
                border: OutlineInputBorder(),
              ),
              items: _labourList.map((l) {
                return DropdownMenuItem<int>(
                  value: l['id'] as int,
                  child: Text(
                      '${l['name']} (${l['labour_type']})'),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedLabourId = val;
                  _paymentHistory = [];
                  _totalEarned = 0;
                  _totalPaid = 0;
                  _balance = 0;
                });
                if (val != null) {
                  _loadLabourSummary(
                      val, _labourList.firstWhere((l) => l['id'] == val)['labour_type'] as String);
                }
              },
              hint: const Text('Select labour...'),
            ),
            const SizedBox(height: 14),

            // Balance Summary Card
            if (_selectedLabourId != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _summaryItem(
                              'Total Earned',
                              '₹${_totalEarned.toStringAsFixed(2)}',
                              Colors.blue.shade700),
                          _summaryItem(
                              'Total Paid',
                              '₹${_totalPaid.toStringAsFixed(2)}',
                              Colors.green.shade700),
                          _summaryItem(
                              'Balance Due',
                              '₹${_balance.toStringAsFixed(2)}',
                              _balance > 0
                                  ? Colors.red.shade700
                                  : Colors.green.shade700),
                        ],
                      ),
              ),

            const SizedBox(height: 16),

            // Payment Form
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Record Payment',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.indigo)),
                  const SizedBox(height: 10),

                  // Amount
                  TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹) *',
                      border: OutlineInputBorder(),
                      prefixText: '₹ ',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'))
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Amount is required';
                      }
                      final val = double.tryParse(v.trim());
                      if (val == null || val <= 0) {
                        return 'Enter a valid amount > 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Date
                  TextFormField(
                    controller: _dateCtrl,
                    readOnly: true,
                    onTap: _pickDate,
                    decoration: const InputDecoration(
                      labelText: 'Payment Date *',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Date is required' : null,
                  ),
                  const SizedBox(height: 12),

                  // Payment Mode
                  DropdownButtonFormField<String>(
                    value: _paymentMode,
                    decoration: const InputDecoration(
                      labelText: 'Payment Mode *',
                      border: OutlineInputBorder(),
                    ),
                    items: _paymentModes
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _paymentMode = v!),
                  ),
                  const SizedBox(height: 12),

                  // Reference
                  TextFormField(
                    controller: _referenceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reference Number',
                      border: OutlineInputBorder(),
                      hintText: 'Cheque no. / UPI ref (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Notes
                  TextFormField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _savePayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Save Payment',
                              style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Payment History
            if (_selectedLabourId != null && _paymentHistory.isNotEmpty) ...[
              const Text('Payment History',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.indigo)),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _paymentHistory.length,
                itemBuilder: (context, index) {
                  final p = _paymentHistory[index];
                  final double amt = (p['amount'] as num).toDouble();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: const CircleAvatar(
                        radius: 16,
                        backgroundColor: Color(0xFFE8EAF6),
                        child: Icon(Icons.currency_rupee,
                            size: 16, color: Colors.indigo),
                      ),
                      title: Text('₹${amt.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${_formatDate(p['payment_date'] as String)}  •  ${p['payment_mode'] ?? ''}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: p['reference_number'] != null
                          ? Text(p['reference_number'] as String,
                              style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11))
                          : null,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        const SizedBox(height: 2),
        Text(label,
            style:
                TextStyle(color: Colors.grey.shade600, fontSize: 11)),
      ],
    );
  }
}
