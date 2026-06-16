import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';

class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  String _selectedFilter = 'This Month';
  final List<String> _filters = ['This Month', 'Last Month', 'This Year', 'Custom'];

  DateTime? _customStart;
  DateTime? _customEnd;

  double _totalIncome = 0;
  double _totalExpenses = 0;
  double _netProfit = 0;
  List<Map<String, dynamic>> _expenseBreakdown = [];
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
      return DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 0, 23, 59, 59));
    } else if (_selectedFilter == 'Last Month') {
      return DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: DateTime(now.year, now.month, 0, 23, 59, 59));
    } else if (_selectedFilter == 'This Year') {
      return DateTimeRange(start: DateTime(now.year, 1, 1), end: DateTime(now.year, 12, 31, 23, 59, 59));
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

    final incomeRows = await db.rawQuery(
      "SELECT SUM(amount) as total FROM payments WHERE payment_date BETWEEN ? AND ?",
      [start, end],
    );
    final income = (incomeRows.first['total'] as num?)?.toDouble() ?? 0.0;

    final expenseRows = await db.rawQuery(
      "SELECT category, SUM(amount) as total FROM expenses WHERE expense_date BETWEEN ? AND ? GROUP BY category ORDER BY total DESC",
      [start, end],
    );
    double totalExp = 0;
    final breakdown = <Map<String, dynamic>>[];
    for (final r in expenseRows) {
      final amt = (r['total'] as num).toDouble();
      totalExp += amt;
      breakdown.add({'category': r['category'], 'total': amt});
    }

    setState(() {
      _totalIncome = income;
      _totalExpenses = totalExp;
      _netProfit = income - totalExp;
      _expenseBreakdown = breakdown;
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
    final isProfit = _netProfit >= 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profit & Loss'),
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
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: isProfit ? Colors.green[50] : Colors.red[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              isProfit ? 'NET PROFIT' : 'NET LOSS',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isProfit ? Colors.green[700] : Colors.red[700], letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₹${_formatAmount(_netProfit.abs())}',
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isProfit ? Colors.green[700] : Colors.red[700]),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _plRow('Total Income (Payments Received)', _totalIncome, Colors.green),
                            const Divider(),
                            _plRow('Total Expenses', _totalExpenses, Colors.red),
                            const Divider(thickness: 2),
                            _plRow(isProfit ? 'Net Profit' : 'Net Loss', _netProfit.abs(), isProfit ? Colors.green : Colors.red, bold: true),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_expenseBreakdown.isNotEmpty) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Expense Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(height: 8),
                      ..._expenseBreakdown.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(e['category'], style: const TextStyle(color: Colors.black87)),
                            Text('₹${_formatAmount(e['total'])}', style: const TextStyle(color: Colors.red)),
                          ],
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

  Widget _plRow(String label, double amount, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 15 : 14)),
          Text('₹${_formatAmount(amount)}', style: TextStyle(color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 15 : 14)),
        ],
      ),
    );
  }
}
