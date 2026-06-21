import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  Map<String, dynamic>? _invoice;
  Map<String, dynamic>? _customer;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;
  bool _isCancelling = false;
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      _isInit = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args != null && args is Map<String, dynamic>) {
        _invoice = Map<String, dynamic>.from(args);
        _loadData();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final database = await _db.database;

    // Load fresh invoice
    final invRows = await database.query(
      'invoices', where: 'id = ?', whereArgs: [_invoice!['id']]);
    if (invRows.isEmpty) { setState(() => _isLoading = false); return; }
    _invoice = Map<String, dynamic>.from(invRows.first);

    // Load customer
    final custRows = await database.query(
      'customers', where: 'id = ?', whereArgs: [_invoice!['customer_id']]);
    if (custRows.isNotEmpty) _customer = custRows.first;

    // Load invoice items with product name
    final itemRows = await database.rawQuery(
      'SELECT ii.*, p.product_name FROM invoice_items ii '
      'JOIN products p ON ii.product_id = p.id '
      'WHERE ii.invoice_id = ?', [_invoice!['id']]);
    _items = itemRows;

    // Load payments for this customer
    final payRows = await database.query(
      'payments',
      where: 'customer_id = ?',
      whereArgs: [_invoice!['customer_id']],
      orderBy: 'payment_date DESC');
    _payments = payRows;

    setState(() => _isLoading = false);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Paid': return Colors.green;
      case 'Partially Paid': return Colors.orange;
      case 'Cancelled': return Colors.red;
      default: return Colors.blue;
    }
  }

  Future<void> _cancelInvoice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Invoice'),
        content: const Text(
          'Cancelling this invoice will return stock and reverse all ledger entries. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isCancelling = true);
    try {
      final database = await _db.database;
      final int invoiceId = _invoice!['id'] as int;
      final String now = DateTime.now().toIso8601String();
      await database.transaction((txn) async {
        // Reverse stock for each item
        for (final item in _items) {
          await txn.insert('stock_in', {
            'product_id': item['product_id'],
            'movement_type': 'Sold Reversed',
            'quantity': item['quantity'],
            'unit': item['unit'],
            'reference': _invoice!['invoice_number'],
            'movement_date': now.substring(0, 10),
          });
        }
        // Set invoice cancelled
        await txn.update('invoices',
          {'status': 'Cancelled', 'cancelled_at': now},
          where: 'id = ?', whereArgs: [invoiceId]);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice cancelled'),
            backgroundColor: Colors.orange));
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to cancel. Please try again.'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invoice == null) {
      return const Scaffold(body: Center(child: Text('No invoice selected')));
    }
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final status = _invoice!['status'] as String? ?? 'Unpaid';
    final total = (_invoice!['total_amount'] as num?)?.toDouble() ?? 0.0;
    final paid = (_invoice!['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final balance = (_invoice!['balance'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_invoice!['invoice_number'] ?? 'Invoice Detail'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Invoice Header Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_customer?['name'] ?? '',
                          style: const TextStyle(fontSize: 16,
                            fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _statusColor(status)),
                          ),
                          child: Text(status,
                            style: TextStyle(
                              color: _statusColor(status),
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Date: ${_invoice!["invoice_date"] ?? ""}'),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Amount:'),
                        Text('${total.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      ]),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Paid Amount:'),
                        Text('${paid.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold)),
                      ]),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Balance Due:'),
                        Text('${balance.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: balance > 0 ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold)),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Line Items
            const Text('Items',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    const Row(children: [
                      Expanded(flex: 3, child: Text('Product',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 2, child: Text('Qty',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 2, child: Text('Rate',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 2, child: Text('Amount',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    ]),
                    const Divider(),
                    ..._items.map((item) {
                      final qty = (item['quantity'] as num).toDouble();
                      final rate = (item['rate'] as num).toDouble();
                      final amt = (item['amount'] as num).toDouble();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(flex: 3, child: Text(
                            item['product_name'] ?? '',
                            style: const TextStyle(fontSize: 12))),
                          Expanded(flex: 2, child: Text(
                            '${qty.toStringAsFixed(2)} ${item["unit"] ?? ""}',
                            style: const TextStyle(fontSize: 12))),
                          Expanded(flex: 2, child: Text(
                            rate.toStringAsFixed(2),
                            style: const TextStyle(fontSize: 12))),
                          Expanded(flex: 2, child: Text(
                            amt.toStringAsFixed(2),
                            style: const TextStyle(fontSize: 12))),
                        ]),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Payment History
            if (_payments.isNotEmpty) ...[
              const Text('Payment History',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              ..._payments.map((p) {
                final amt = (p['amount'] as num).toDouble();
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.currency_rupee,
                      color: Colors.green),
                    title: Text('${amt.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${p["payment_date"] ?? ""}  •  ${p["payment_mode"] ?? ""}'),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],

            // Cancel Button
            if (status != 'Cancelled')
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: _isCancelling
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cancel_outlined, color: Colors.red),
                  label: const Text('Cancel Invoice',
                    style: TextStyle(color: Colors.red, fontSize: 16)),
                  onPressed: _isCancelling ? null : _cancelInvoice,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
