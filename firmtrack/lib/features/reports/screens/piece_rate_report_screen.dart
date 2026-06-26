import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';

class PieceRateReportScreen extends StatefulWidget {
  const PieceRateReportScreen({super.key});

  @override
  State<PieceRateReportScreen> createState() => _PieceRateReportScreenState();
}

class _PieceRateReportScreenState extends State<PieceRateReportScreen> {
  final NumberFormat _fmt = NumberFormat('##,##,##0.00', 'en_IN');

  List<Map<String, dynamic>> _labourList = [];
  int? _selectedLabourId;
  DateTime? _fromDate;
  DateTime? _toDate;

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
      "SELECT id, name FROM labour WHERE labour_type = 'Piece Rate' ORDER BY name ASC",
    );
    setState(() => _labourList = rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? DateTime(now.year, now.month, 1)) : (_toDate ?? now),
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  Future<void> _loadReport() async {
    setState(() { _loading = true; _hasResult = false; });
    final db = await DatabaseHelper.instance.database;

    List<Map<String, dynamic>> labourToReport = [];
    if (_selectedLabourId != null) {
      labourToReport = _labourList.where((l) => l['id'] == _selectedLabourId).toList();
    } else {
      labourToReport = _labourList;
    }

    String dateFilter = '';
    List<dynamic> dateParams = [];
    if (_fromDate != null && _toDate != null) {
      dateFilter = 'AND lp.production_date BETWEEN ? AND ?';
      dateParams = [_fromDate!.toIso8601String(), _toDate!.toIso8601String()];
    }

    final list = <Map<String, dynamic>>[];

    for (final l in labourToReport) {
      final lid = l['id'] as int;

      // Get production items for this labour
      final prodRows = await db.rawQuery(
        """SELECT p.product_name, SUM(lpi.quantity_made) as total_qty,
           lpi.unit_made, SUM(lpi.amount) as total_earned
           FROM labour_production_items lpi
           JOIN labour_production lp ON lpi.production_id = lp.id
           JOIN products p ON lpi.product_id = p.id
           WHERE lp.labour_id = ? AND lp.status = 'Active' $dateFilter
           GROUP BY lpi.product_id, lpi.unit_made
           ORDER BY p.product_name ASC""",
        [lid, ...dateParams],
      );

      if (prodRows.isEmpty) continue;

      double totalEarned = 0;
      for (final r in prodRows) {
        totalEarned += (r['total_earned'] as num).toDouble();
      }

      // Total paid all time
      final paidRows = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) as total FROM labour_payments WHERE labour_id=?",
        [lid],
      );
      final totalPaid = (paidRows.first['total'] as num).toDouble();

      // Total earned all time for balance
      final allEarnedRows = await db.rawQuery(
        "SELECT COALESCE(SUM(total_earned),0) as total FROM labour_production WHERE labour_id=? AND status='Active'",
        [lid],
      );
      final allTimeEarned = (allEarnedRows.first['total'] as num).toDouble();
      final balance = allTimeEarned - totalPaid;

      list.add({
        'name': l['name'],
        'products': prodRows.map((r) => Map<String, dynamic>.from(r)).toList(),
        'period_earned': totalEarned,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Piece Rate Labour Report'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
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
                    const DropdownMenuItem<int>(value: null, child: Text('All Piece Rate Labour')),
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
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_fromDate == null ? 'From Date' : DateFormat('dd MMM yyyy').format(_fromDate!)),
                        onPressed: () => _pickDate(true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_toDate == null ? 'To Date' : DateFormat('dd MMM yyyy').format(_toDate!)),
                        onPressed: () => _pickDate(false),
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
                  ? const Center(child: Text('No production data found.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        final products = r['products'] as List<Map<String, dynamic>>;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const Divider(height: 12),
                                ...products.map((p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text(p['product_name'], style: const TextStyle(fontSize: 13))),
                                      Text('${_fmt2((p['total_qty'] as num).toDouble())} ${p['unit_made']}', style: const TextStyle(fontSize: 13, color: Colors.indigo)),
                                      const SizedBox(width: 8),
                                      Text('₹${_fmt2((p['total_earned'] as num).toDouble())}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                )),
                                const Divider(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Period Earned: ₹${_fmt2(r['period_earned'])}', style: const TextStyle(color: Colors.blue, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Total Paid: ₹${_fmt2(r['total_paid'])}', style: const TextStyle(color: Colors.green, fontSize: 13)),
                                    Text('Balance: ₹${_fmt2(r['balance'])}', style: TextStyle(color: r['balance'] > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
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
}
