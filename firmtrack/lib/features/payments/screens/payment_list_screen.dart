import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';

class PaymentListScreen extends StatefulWidget {
  const PaymentListScreen({super.key});

  @override
  State<PaymentListScreen> createState() => _PaymentListScreenState();
}

class _PaymentListScreenState extends State<PaymentListScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _isLoading = true);
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT p.*, c.name as customer_name '
      'FROM payments p '
      'LEFT JOIN customers c ON p.customer_id = c.id '
      'ORDER BY p.payment_date DESC, p.created_at DESC');
    setState(() {
      _payments = rows;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPayments,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(context, '/payment-form');
          _loadPayments();
        },
        backgroundColor: const Color(0xFF1976D2),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _payments.isEmpty
          ? const Center(child: Text('No payments recorded yet'))
          : ListView.builder(
              itemCount: _payments.length,
              itemBuilder: (ctx, i) {
                final p = _payments[i];
                final amt = (p['amount'] as num).toDouble();
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE3F2FD),
                      child: const Icon(Icons.currency_rupee,
                        color: Color(0xFF1976D2)),
                    ),
                    title: Text(
                      p['customer_name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${p["payment_date"] ?? ""}  •  ${p["payment_mode"] ?? ""}'),
                    trailing: Text(
                      'Rs.${amt.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontSize: 14)),
                  ),
                );
              },
            ),
    );
  }
}
