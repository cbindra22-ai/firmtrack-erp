import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';
import '../services/payment_collection_pdf_service.dart';

class PaymentCollectionReportScreen extends StatefulWidget {
  const PaymentCollectionReportScreen({super.key});

  @override
  State<PaymentCollectionReportScreen> createState() => _PaymentCollectionReportScreenState();
}

class _PaymentCollectionReportScreenState extends State<PaymentCollectionReportScreen> {
  final NumberFormat _fmt = NumberFormat('##,##,##0.00', 'en_IN');

  List<Map<String, dynamic>> _customerList = [];
  int? _selectedCustomerId;
  String _selectedMode = 'All';
  final List<String> _modes = ['All', 'Cash', 'UPI', 'Cheque', 'Bank Transfer'];

  DateTime? _fromDate;
  DateTime? _toDate;

  List<Map<String, dynamic>> _rows = [];
  double _totalAmount = 0;
  bool _loading = false;
  bool _hasResult = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('customers', orderBy: 'name ASC');
    setState(() => _customerList = rows.map((r) => Map<String, dynamic>.from(r)).toList());
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

    String whereClause = 'WHERE 1=1';
    List<dynamic> params = [];

    if (_fromDate != null && _toDate != null) {
      whereClause += ' AND p.payment_date BETWEEN ? AND ?';
      params.addAll([_fromDate!.toIso8601String(), _toDate!.toIso8601String()]);
    }

    if (_selectedCustomerId != null) {
      whereClause += ' AND p.customer_id = ?';
      params.add(_selectedCustomerId);
    }

    if (_selectedMode != 'All') {
      whereClause += ' AND p.payment_mode = ?';
      params.add(_selectedMode);
    }

    final rows = await db.rawQuery(
      """SELECT p.payment_date, c.name as customer_name, p.payment_mode,
         p.reference_number, p.amount, p.notes
         FROM payments p
         JOIN customers c ON p.customer_id = c.id
         $whereClause
         ORDER BY p.payment_date DESC""",
      params,
    );

    double total = 0;
    for (final r in rows) {
      total += (r['amount'] as num).toDouble();
    }

    setState(() {
      _rows = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      _totalAmount = total;
      _loading = false;
      _hasResult = true;
    });
  }

  String _fmt2(double v) => _fmt.format(v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Collection Report'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        actions: [
          if (_hasResult)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Export PDF',
              onPressed: () {
                final from = _fromDate == null ? 'All' : _fromDate!.toString().substring(0, 10);
                final to = _toDate == null ? 'All' : _toDate!.toString().substring(0, 10);
                final periodLabel = _fromDate == null ? 'All Dates' : '$from to $to';
                final customerLabel = _selectedCustomerId == null ? 'All' : _customerList.firstWhere((c) => c['id'] == _selectedCustomerId)['name'].toString();
                PaymentCollectionPdfService.generateAndShare(
                  context: context,
                  periodLabel: periodLabel,
                  customerLabel: customerLabel,
                  modeLabel: _selectedMode,
                  totalAmount: _totalAmount,
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
                  value: _selectedCustomerId,
                  decoration: const InputDecoration(labelText: 'Customer (All if not selected)', border: OutlineInputBorder(), isDense: true),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('All Customers')),
                    ..._customerList.map((c) => DropdownMenuItem<int>(
                      value: c['id'] as int,
                      child: Text(c['name'] as String),
                    )),
                  ],
                  onChanged: (v) => setState(() => _selectedCustomerId = v),
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
                DropdownButtonFormField<String>(
                  value: _selectedMode,
                  decoration: const InputDecoration(labelText: 'Payment Mode', border: OutlineInputBorder(), isDense: true),
                  items: _modes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setState(() => _selectedMode = v ?? 'All'),
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
          else if (_hasResult) ...[
            Container(
              color: Colors.cyan[50],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Collected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('₹${_fmt2(_totalAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan, fontSize: 16)),
                ],
              ),
            ),
            Expanded(
              child: _rows.isEmpty
                  ? const Center(child: Text('No payments found.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        final ref = r['reference_number']?.toString() ?? '';
                        final notes = r['notes']?.toString() ?? '';
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
                                    Text(r['customer_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    Text('₹${_fmt2((r['amount'] as num).toDouble())}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(r['payment_date'].toString().substring(0, 10), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                      child: Text(r['payment_mode'], style: const TextStyle(fontSize: 12, color: Colors.cyan)),
                                    ),
                                  ],
                                ),
                                if (ref.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text('Ref: $ref', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                ],
                                if (notes.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text('Note: $notes', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
