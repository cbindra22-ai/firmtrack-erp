import 'package:flutter/material.dart';
// ignore: unused_import
import '../../../core/database/database_helper.dart';

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  List<Map<String, dynamic>> _invoices = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() => _isLoading = true);
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('''
      SELECT i.*, c.name as customer_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      ORDER BY i.created_at DESC
    ''');
    setState(() {
      _invoices = result;
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _invoices;
    final q = _searchQuery.toLowerCase();
    return _invoices.where((inv) {
      return (inv['invoice_number'] ?? '').toString().toLowerCase().contains(q) ||
          (inv['customer_name'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Paid':
        return Colors.green;
      case 'Partially Paid':
        return Colors.orange;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _cancelInvoice(Map<String, dynamic> invoice) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Invoice'),
        content: Text(
            'Cancel invoice ${invoice['invoice_number']}? This will reverse stock and any advance applied.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      // Get invoice items
      final items = await txn.query('invoice_items',
          where: 'invoice_id = ?', whereArgs: [invoice['id']]);

      // Reverse stock for each item
      for (final item in items) {
        await txn.insert('stock_in', {
          'product_id': item['product_id'],
          'quantity': item['quantity'],
          'movement_type': 'Sold Reversed',
          'reference': invoice['invoice_number'],
          'movement_date': DateTime.now().toIso8601String().substring(0, 10),
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // Reverse advance if applied
      // advance is runtime calculated - no column to update

      // Update invoice status
      await txn.update('invoices', {'status': 'Cancelled'},
          where: 'id = ?', whereArgs: [invoice['id']]);
    });

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invoice cancelled successfully')));
      _loadInvoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInvoices,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(context, '/invoice-form');
          _loadInvoices();
        },
        backgroundColor: const Color(0xFF1976D2),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by invoice no or customer...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(child: Text('No invoices found'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final inv = filtered[i];
                          final status = inv['status'] ?? 'Unpaid';
                          final total = (inv['total_amount'] ?? 0.0) as num;
                          final balance = (inv['balance'] ?? 0.0) as num;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            child: ListTile(
                              onTap: () async {
                                await Navigator.pushNamed(context, '/invoice-detail', arguments: inv);
                                _loadInvoices();
                              },
                              title: Row(
                                children: [
                                  Text(inv['invoice_number'] ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _statusColor(status)),
                                    ),
                                    child: Text(status,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: _statusColor(status),
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(inv['customer_name'] ?? 'Unknown Customer'),
                                  Text('Date: ${inv['invoice_date'] ?? ''}'),
                                  Row(
                                    children: [
                                      Text('Total: ₹${total.toStringAsFixed(2)}'),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Balance: ₹${balance.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: balance > 0 ? Colors.red : Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: status != 'Cancelled'
                                  ? PopupMenuButton<String>(
                                      onSelected: (val) {
                                        if (val == 'cancel') _cancelInvoice(inv);
                                      },
                                      itemBuilder: (ctx) => [
                                        const PopupMenuItem(
                                            value: 'cancel',
                                            child: Text('Cancel Invoice',
                                                style: TextStyle(color: Colors.red))),
                                      ],
                                    )
                                  : const Icon(Icons.block, color: Colors.red),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
