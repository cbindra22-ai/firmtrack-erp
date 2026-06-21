import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';

class PaymentFormScreen extends StatefulWidget {
  const PaymentFormScreen({super.key});

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<Map<String, dynamic>> _customers = [];
  int? _selectedCustomerId;
  double _outstanding = 0.0;
  double _advance = 0.0;
  bool _isLoadingCustomers = false;
  bool _isLoadingSummary = false;
  bool _isSaving = false;

  String _paymentMode = 'Cash';
  DateTime _selectedDate = DateTime.now();
  final List<String> _paymentModes = ['Cash', 'UPI', 'Cheque', 'Bank Transfer'];

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoadingCustomers = true);
    final db = await _db.database;
    final rows = await db.query('customers', orderBy: 'name ASC');
    setState(() {
      _customers = rows;
      _isLoadingCustomers = false;
    });
  }

  Future<void> _loadCustomerSummary(int customerId) async {
    setState(() => _isLoadingSummary = true);
    final db = await _db.database;

    final outRows = await db.rawQuery(
      'SELECT COALESCE(SUM(balance), 0) as total FROM invoices '
      'WHERE customer_id = ? AND status IN (?, ?)',
      [customerId, 'Unpaid', 'Partially Paid']);
    final outstanding = (outRows.first['total'] as num?)?.toDouble() ?? 0.0;

    final totalPaidRows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM payments WHERE customer_id = ?',
      [customerId]);
    final totalPaid = (totalPaidRows.first['total'] as num?)?.toDouble() ?? 0.0;

    final totalInvRows = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount), 0) as total FROM invoices '
      'WHERE customer_id = ? AND status != ?',
      [customerId, 'Cancelled']);
    final totalInv = (totalInvRows.first['total'] as num?)?.toDouble() ?? 0.0;

    final advance = (totalPaid - totalInv) > 0 ? (totalPaid - totalInv) : 0.0;

    setState(() {
      _outstanding = outstanding;
      _advance = advance;
      _isLoadingSummary = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _savePayment() async {
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer'),
          backgroundColor: Colors.red));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final db = await _db.database;
      final double amount = double.parse(_amountCtrl.text.trim());
      final String date = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final int customerId = _selectedCustomerId!;

      await db.transaction((txn) async {
        await txn.insert('payments', {
          'customer_id': customerId,
          'amount': amount,
          'payment_date': date,
          'payment_mode': _paymentMode,
          'reference_number': _referenceCtrl.text.trim().isEmpty
            ? null : _referenceCtrl.text.trim(),
          'notes': _notesCtrl.text.trim().isEmpty
            ? null : _notesCtrl.text.trim(),
        });

        // BR-PAY-01 auto allocate oldest unpaid invoices first
        final invoices = await txn.query(
          'invoices',
          where: 'customer_id = ? AND status IN (?, ?)',
          whereArgs: [customerId, 'Unpaid', 'Partially Paid'],
          orderBy: 'invoice_date ASC');

        double remaining = amount;
        for (final inv in invoices) {
          if (remaining <= 0) break;
          final invBalance = (inv['balance'] as num).toDouble();
          final invPaid = (inv['paid_amount'] as num).toDouble();
          if (remaining >= invBalance) {
            await txn.update('invoices', {
              'paid_amount': invPaid + invBalance,
              'balance': 0.0,
              'status': 'Paid',
            }, where: 'id = ?', whereArgs: [inv['id']]);
            remaining -= invBalance;
          } else {
            await txn.update('invoices', {
              'paid_amount': invPaid + remaining,
              'balance': invBalance - remaining,
              'status': 'Partially Paid',
            }, where: 'id = ?', whereArgs: [inv['id']]);
            remaining = 0;
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment saved successfully'),
            backgroundColor: Colors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save. Please try again.'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Payment'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _isLoadingCustomers
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<int>(
                    value: _selectedCustomerId,
                    decoration: const InputDecoration(
                      labelText: 'Select Customer *',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select customer...'),
                    items: _customers.map((c) {
                      return DropdownMenuItem<int>(
                        value: c['id'] as int,
                        child: Text(c['name'] as String),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedCustomerId = val;
                        _outstanding = 0;
                        _advance = 0;
                      });
                      if (val != null) _loadCustomerSummary(val);
                    },
                  ),
              const SizedBox(height: 12),

              if (_selectedCustomerId != null)
                _isLoadingSummary
                  ? const Center(child: CircularProgressIndicator())
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1976D2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(children: [
                            Text('Outstanding',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            Text('Rs.${_outstanding.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold,
                                color: Colors.red, fontSize: 14)),
                          ]),
                          Column(children: [
                            Text('Advance',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            Text('Rs.${_advance.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold,
                                color: Colors.green, fontSize: 14)),
                          ]),
                        ],
                      ),
                    ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (Rs.) *',
                  prefixText: 'Rs. ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Amount is required';
                  final val = double.tryParse(v.trim());
                  if (val == null || val <= 0) return 'Enter valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Payment Date *',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _paymentMode,
                decoration: const InputDecoration(
                  labelText: 'Payment Mode *',
                  border: OutlineInputBorder(),
                ),
                items: _paymentModes.map((m) =>
                  DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => _paymentMode = v!),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _referenceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reference Number',
                  border: OutlineInputBorder(),
                  hintText: 'UPI ref / Cheque no (optional)',
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _savePayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                  ),
                  child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Payment', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
