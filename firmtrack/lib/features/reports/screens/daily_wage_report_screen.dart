import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';
import '../services/daily_wage_report_pdf_service.dart';

class DailyWageReportScreen extends StatefulWidget {
  const DailyWageReportScreen({super.key});

  @override
  State<DailyWageReportScreen> createState() => _DailyWageReportScreenState();
}

class _DailyWageReportScreenState extends State<DailyWageReportScreen> {
  final NumberFormat _fmt = NumberFormat('##,##,##0.00', 'en_IN');

  List<Map<String, dynamic>> _labourList = [];
  int? _selectedLabourId;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  bool _hasResult = false;

  @override
  void initState() {
    super.initState();
    _loadLabour();
  }

  Future<void> _loadLabour() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      "SELECT id, name FROM labour WHERE labour_type = 'Daily Wage' ORDER BY name ASC",
    );
    setState(() => _labourList = rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }

  Future<void> _loadReport() async {
    setState(() { _loading = true; _hasResult = false; });
    final db = await DatabaseHelper.instance.database;

    final fromDate = '$_selectedYear-${_selectedMonth.toString().padLeft(2,'0')}-01';
    final lastDay = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final toDate = '$_selectedYear-${_selectedMonth.toString().padLeft(2,'0')}-${lastDay.toString().padLeft(2,'0')}';

    // Get labour list to report on
    List<Map<String, dynamic>> labourToReport = [];
    if (_selectedLabourId != null) {
      labourToReport = _labourList.where((l) => l['id'] == _selectedLabourId).toList();
    } else {
      labourToReport = _labourList;
    }

    final list = <Map<String, dynamic>>[];

    for (final l in labourToReport) {
      final lid = l['id'] as int;

      // Get wage rate
      final labourRows = await db.rawQuery(
        "SELECT daily_wage_rate FROM labour WHERE id=?", [lid],
      );
      final wageRate = (labourRows.first['daily_wage_rate'] as num?)?.toDouble() ?? 0.0;

      // Get attendance for month
      final attRows = await db.rawQuery(
        "SELECT status FROM labour_attendance WHERE labour_id=? AND attendance_date BETWEEN ? AND ?",
        [lid, fromDate, toDate],
      );

      int present = 0;
      int halfDay = 0;
      int absent = 0;
      for (final a in attRows) {
        final s = a['status'] as String;
        if (s == 'Present') present++;
        else if (s == 'Half Day') halfDay++;
        else if (s == 'Absent') absent++;
      }

      final earned = (present * wageRate) + (halfDay * wageRate / 2);

      // Total paid
      final paidRows = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) as total FROM labour_payments WHERE labour_id=?",
        [lid],
      );
      final totalPaid = (paidRows.first['total'] as num).toDouble();

      // Total earned all time to calculate balance
      final allAttRows = await db.rawQuery(
        "SELECT status FROM labour_attendance WHERE labour_id=?",
        [lid],
      );
      double totalEarned = 0;
      for (final a in allAttRows) {
        final s = a['status'] as String;
        if (s == 'Present') totalEarned += wageRate;
        else if (s == 'Half Day') totalEarned += wageRate / 2;
      }
      final balance = totalEarned - totalPaid;

      list.add({
        'name': l['name'],
        'present': present,
        'half_day': halfDay,
        'absent': absent,
        'earned_this_month': earned,
        'total_paid': totalPaid,
        'balance': balance,
      });
    }

    setState(() {
      _rows = list;
      _loading = false;
      _hasResult = true;
    });
  }

  String _fmt2(double v) => _fmt.format(v);

  @override
  Widget build(BuildContext context) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final years = List.generate(5, (i) => DateTime.now().year - i);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Wage Labour Report'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        actions: [
          if (_hasResult)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Export PDF',
              onPressed: () {
                final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                final periodLabel = '${months[_selectedMonth-1]} $_selectedYear';
                final labourLabel = _selectedLabourId == null ? 'All' : _labourList.firstWhere((l) => l['id'] == _selectedLabourId)['name'].toString();
                DailyWageReportPdfService.generateAndShare(
                  context: context,
                  periodLabel: periodLabel,
                  labourLabel: labourLabel,
                  rows: _rows,
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButtonFormField<int>(
                  value: _selectedLabourId,
                  decoration: const InputDecoration(labelText: 'Labour (All if not selected)', border: OutlineInputBorder(), isDense: true),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('All Daily Wage Labour')),
                    ..._labourList.map((l) => DropdownMenuItem<int>(
                      value: l['id'] as int,
                      child: Text(l['name'] as String),
                    )),
                  ],
                  onChanged: (v) => setState(() => _selectedLabourId = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _selectedMonth,
                        decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder(), isDense: true),
                        items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                        onChanged: (v) => setState(() => _selectedMonth = v ?? _selectedMonth),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _selectedYear,
                        decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder(), isDense: true),
                        items: years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                        onChanged: (v) => setState(() => _selectedYear = v ?? _selectedYear),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loadReport,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), foregroundColor: Colors.white),
                    child: const Text('VIEW REPORT'),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_hasResult)
            Expanded(
              child: _rows.isEmpty
                  ? const Center(child: Text('No data found.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _attChip('Present', r['present'], Colors.green),
                                    _attChip('Half Day', r['half_day'], Colors.orange),
                                    _attChip('Absent', r['absent'], Colors.red),
                                  ],
                                ),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Earned (this month): ₹${_fmt2(r['earned_this_month'])}', style: const TextStyle(color: Colors.blue)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Total Paid: ₹${_fmt2(r['total_paid'])}', style: const TextStyle(color: Colors.green)),
                                    Text('Balance: ₹${_fmt2(r['balance'])}', style: TextStyle(color: r['balance'] > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
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

  Widget _attChip(String label, int count, Color color) {
    return Column(
      children: [
        Text(count.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}
