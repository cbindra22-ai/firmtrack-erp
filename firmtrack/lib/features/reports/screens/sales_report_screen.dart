import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  String _selectedFilter = 'This Month';
  final List<String> _filters = ['This Month', 'Last Month', 'This Year', 'Custom'];

  DateTime? _customStart;
  DateTime? _customEnd;

  double _totalSales = 0;
  double _totalPaid = 0;
  double _totalBalance = 0;
  List<Map<String, dynamic>> _customerSales = [];
  bool _loading = false;

  final NumberFormat _fmt = NumberFormat('##,##,##0.00', 'en_IN');

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  DateTimeRange _getDateRange() {
    final now = DateTime.now();
    if (_selectedFilter == 'This Month') {
      return DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
      );
    } else if (_selectedFilter == 'Last Month') {
      final first = DateTime(now.year, now.month - 1, 1);
      final last = DateTime(now.year, now.month, 0, 23, 59, 59);
      return DateTimeRange(start: first, end: last);
    } else if (_selectedFilter == 'This Year') {
      return DateTimeRange(
        start: DateTime(now.year, 1, 1),
        end: DateTime(now.year, 12, 31, 23, 59, 59),
      );
    } else {
      return DateTimeRange(
        start: _customStart ?? DateTime(now.year, now.month, 1),
        end: _customEnd ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59),
      );
    }
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.instance.database;
    final range = _getDateRange();
    final start = range.start.toIso8601String();
    final end = range.end.toIso8601String();

    final invoices = await db.rawQuery(
      "SELECT i.id, i.customer_id, c.name as customer_name, i.total_amount, i.paid_amount, i.balance_amount FROM invoices i LEFT JOIN customers c ON i.customer_id = c.id WHERE i.status != 'Cancelled' AND i.invoice_date BETWEEN ? AND ?",
      [start, end],
    );

    double totalSales = 0;
    double totalPaid = 0;
    double totalBalance = 0;
    final Map<int, Map<String, dynamic>> byCustomer = {};

    for (final inv in invoices) {
      totalSales += (inv['total_amount'] as num).toDouble();
      totalPaid += (inv['paid_amount'] as num).toDouble();
      totalBalance += (inv['balance_amount'] as num).toDouble();
      final cid = inv['customer_id'] as int;
      if (!byCustomer.containsKey(cid)) {
        byCustomer[cid] = {
          'name': inv['customer_name'] ?? 'Unknown',
          'total': 0.0,
          'paid': 0.0,
          'balance': 0.0,
        };
      }
      byCustomer[cid]!['total'] += (inv['total_amount'] as num).toDouble();
      byCustomer[cid]!['paid'] += (inv['paid_amount'] as num).toDouble();
      byCustomer[cid]!['balance'] += (inv['balance_amount'] as num).toDouble();
    }

    setState(() {
      _totalSales = totalSales;
      _totalPaid = totalPaid;
      _totalBalance = totalBalance;
      _customerSales = byCustomer.values.toList();
      _loading = false;
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final start = await showDatePicker(
      context: context,
      initialDate: _customStart ?? DateTime(now.year, now.month, 1),
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Select Start Date',
    );
    if (start == null) return;
    if (!mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate: _customEnd ?? now,
      firstDate: start,
      lastDate: now,
      helpText: 'Select End Date',
    );
    if (end == null) return;
    setState(() {
      _customStart = start;
      _customEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
    });
    _loadReport();
  }

  String _formatAmount(double v) => _fmt.format(v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Report'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((f) {
                  final selected = _selectedFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: selected,
                      onSelected: (_) async {
                        setState(() => _selectedFilter = f);
                        if (f == 'Custom') {
                          await _pickCustomRange();
                        } else {
                          _loadReport();
                        }
                      },
                      selectedColor: const Color(0xFF1976D2),
                      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _summaryCard('Total Invoiced', _totalSales, Colors.blue),
                        const SizedBox(width: 8),
                        _summaryCard('Received', _totalPaid, Colors.green),
                        const SizedBox(width: 8),
                        _summaryCard('Pending', _totalBalance, Colors.red),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_customerSales.isEmpty)
                      const Center(child: Text('No sales in this period.'))
                    else ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('By Customer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(height: 8),
                      ..._customerSales.map((c) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Invoiced: ₹${_formatAmount(c['total'])}', style: const TextStyle(color: Colors.blue)),
                                  Text('Paid: ₹${_formatAmount(c['paid'])}', style: const TextStyle(color: Colors.green)),
                                  Text('Due: ₹${_formatAmount(c['balance'])}', style: TextStyle(color: c['balance'] > 0 ? Colors.red : Colors.green)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, double amount, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('₹${_formatAmount(amount)}', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
