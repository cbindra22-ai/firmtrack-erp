import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';
import '../services/customer_outstanding_pdf_service.dart';

class CustomerOutstandingReportScreen extends StatefulWidget {
  const CustomerOutstandingReportScreen({super.key});

  @override
  State<CustomerOutstandingReportScreen> createState() => _CustomerOutstandingReportScreenState();
}

class _CustomerOutstandingReportScreenState extends State<CustomerOutstandingReportScreen> {
  final NumberFormat _fmt = NumberFormat('##,##,##0.00', 'en_IN');
  List<Map<String, dynamic>> _rows = [];
  double _totalOutstanding = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.instance.database;

    final customers = await db.query('customers', orderBy: 'name ASC');
    final list = <Map<String, dynamic>>[];
    double grandTotal = 0;

    for (final c in customers) {
      final cid = c['id'] as int;

      // Sum of all unpaid/partial invoice balances
      // Opening balance
      final opening = (c['opening_balance'] as num).toDouble();

      // Total paid by customer
      final paidRows = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) as total FROM payments WHERE customer_id=?",
        [cid],
      );
      final totalPaid = (paidRows.first['total'] as num).toDouble();

      // Total invoiced
      final totalInvRows = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount),0) as total FROM invoices WHERE customer_id=? AND status != 'Cancelled'",
        [cid],
      );
      final totalInvoiced = (totalInvRows.first['total'] as num).toDouble();

      final outstanding = opening + totalInvoiced - totalPaid;

      if (outstanding > 0) {
        list.add({
          'name': c['name'],
          'phone': c['phone'] ?? '',
          'outstanding': outstanding,
        });
        grandTotal += outstanding;
      }
    }

    setState(() {
      _rows = list;
      _totalOutstanding = grandTotal;
      _loading = false;
    });
  }

  String _fmt2(double v) => _fmt.format(v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Outstanding'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: () => CustomerOutstandingPdfService.generateAndShare(
              context: context,
              totalOutstanding: _totalOutstanding,
              rows: _rows,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.red[50],
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Outstanding', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('₹${_fmt2(_totalOutstanding)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                    ],
                  ),
                ),
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(child: Text('No outstanding amounts found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _rows.length,
                          itemBuilder: (context, i) {
                            final r = _rows[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.red.withValues(alpha: 0.15),
                                  child: const Icon(Icons.person, color: Colors.red),
                                ),
                                title: Text(r['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: r['phone'] != '' ? Text(r['phone']) : null,
                                trailing: Text(
                                  '₹${_fmt2(r['outstanding'])}',
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
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
