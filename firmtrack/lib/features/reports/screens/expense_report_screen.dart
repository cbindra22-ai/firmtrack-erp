import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';

class ExpenseReportScreen extends StatefulWidget {
  const ExpenseReportScreen({super.key});

  @override
  State<ExpenseReportScreen> createState() => _ExpenseReportScreenState();
}

class _ExpenseReportScreenState extends State<ExpenseReportScreen> {
  String _selectedFilter = 'This Month';
  final List<String> _filters = ['This Month', 'Last Month', 'This Year', 'Custom'];

  DateTime? _customStart;
  DateTime? _customEnd;

  double _totalExpenses = 0;
  List<Map<String, dynamic>> _byCategory = [];
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

    final rows = await db.rawQuery(
      "SELECT category, SUM(amount) as total FROM expenses WHERE expense_date BETWEEN ? AND ? GROUP BY category ORDER BY total DESC",
      [start, end],
    );

    double total = 0;
    final list = <Map<String, dynamic>>[];
    for (final r in rows) {
      final amt = (r['total'] as num).toDouble();
      total += amt;
      list.add({'category': r['category'], 'total': amt});
    }

    setState(() {
      _totalExpenses = total;
      _byCategory = list;
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
        title: const Text('Expense Report'),
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
                      color: Colors.orange[50],
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Expenses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('₹${_formatAmount(_totalExpenses)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_byCategory.isEmpty)
                      const Center(child: Text('No expenses in this period.'))
                    else ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('By Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(height: 8),
                      ..._byCategory.map((c) {
                        final pct = _totalExpenses > 0 ? (c['total'] as double) / _totalExpenses : 0.0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(c['category'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text('₹${_formatAmount(c['total'])}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: pct,
                                  backgroundColor: Colors.orange[50],
                                  color: Colors.orange,
                                  minHeight: 6,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                const SizedBox(height: 4),
                                Text('${(pct * 100).toStringAsFixed(1)}% of total', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
