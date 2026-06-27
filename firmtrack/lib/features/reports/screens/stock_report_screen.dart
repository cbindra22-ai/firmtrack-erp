import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';

class StockReportScreen extends StatefulWidget {
  const StockReportScreen({super.key});

  @override
  State<StockReportScreen> createState() => _StockReportScreenState();
}

class _StockReportScreenState extends State<StockReportScreen> {
  final NumberFormat _fmt = NumberFormat('##,##,##0.##', 'en_IN');

  // Option selection
  int _selectedOption = 1;

  // Product dropdown
  List<Map<String, dynamic>> _products = [];
  int? _selectedProductId;
  String _selectedProductName = '';
  String _selectedProductUnit = '';

  // Date range
  DateTime? _fromDate;
  DateTime? _toDate;

  // Movement type filter
  String _selectedMovementType = 'All Types';
  final List<String> _movementTypes = [
    'All Types', 'Purchase Only', 'Production Only',
    'Consumed Only', 'Sold Only', 'Reversed Only'
  ];

  // Results
  List<Map<String, dynamic>> _movements = [];
  List<Map<String, dynamic>> _allProductsSummary = [];
  double _currentStock = 0;
  bool _loading = false;
  bool _hasResult = false;
  bool _showLowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('products', orderBy: 'product_name ASC');
    setState(() => _products = rows);
  }

  String _formatNum(double v) => _fmt.format(v);

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
    if (_selectedOption != 4 && _selectedProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product')),
      );
      return;
    }
    setState(() { _loading = true; _hasResult = false; });
    final db = await DatabaseHelper.instance.database;

    if (_selectedOption == 4) {
      // All Products Summary
      final products = await db.query('products', orderBy: 'product_name ASC');
      final list = <Map<String, dynamic>>[];
      for (final p in products) {
        final pid = p['id'] as int;
        final unit = p['unit'] as String;
        final minLevel = (p['min_stock_level'] as num).toDouble();

        // Opening stock
        final openRows = await db.rawQuery(
          "SELECT COALESCE(SUM(quantity),0) as total FROM stock_in WHERE product_id=? AND movement_type='Opening Stock'",
          [pid],
        );
        final opening = (openRows.first['total'] as num).toDouble();

        // Total IN from stock_in (Purchase + Manual Addition + Production + reversals IN)
        final inRows = await db.rawQuery(
          "SELECT COALESCE(SUM(quantity),0) as total FROM stock_in WHERE product_id=? AND movement_type IN ('Purchase','Manual Addition','Production','Sold Reversed','Consumed Reversed')",
          [pid],
        );
        final totalIn = (inRows.first['total'] as num).toDouble();

        // Total OUT sold
        final soldRows = await db.rawQuery(
          "SELECT COALESCE(SUM(ii.quantity),0) as total FROM invoice_items ii JOIN invoices i ON ii.invoice_id=i.id WHERE ii.product_id=? AND i.status!='Cancelled'",
          [pid],
        );
        final soldOut = (soldRows.first['total'] as num).toDouble();

        // Total OUT consumed
        final consumedRows = await db.rawQuery(
          "SELECT COALESCE(SUM(lpi.consumed_qty),0) as total FROM labour_production_items lpi JOIN labour_production lp ON lpi.production_id=lp.id WHERE lpi.material_product_id=? AND lp.status='Active'",
          [pid],
        );
        final consumedOut = (consumedRows.first['total'] as num).toDouble();

        // OUT reversals from stock_in (negative quantity)
        final outReversalRows = await db.rawQuery(
          "SELECT COALESCE(SUM(quantity),0) as total FROM stock_in WHERE product_id=? AND movement_type IN ('Production Reversed')",
          [pid],
        );
        final outReversals = (outReversalRows.first['total'] as num).toDouble();

        final totalOut = soldOut + consumedOut + outReversals.abs();
        final current = opening + totalIn - totalOut;
        String status = 'OK';
        if (current <= 0) status = 'CRITICAL';
        else if (minLevel > 0 && current < minLevel) status = 'LOW';

        list.add({
          'product_name': p['product_name'],
          'unit': unit,
          'opening': opening,
          'total_in': totalIn,
          'total_out': totalOut,
          'current': current,
          'min_level': minLevel,
          'status': status,
        });
      }
      setState(() {
        _allProductsSummary = list;
        _loading = false;
        _hasResult = true;
      });
      return;
    }

    if (_selectedOption == 3) {
      // Production Only
      final rows = await db.rawQuery(
        """SELECT lp.production_date as movement_date, l.name as labour_name,
           p.product_name, lpi.quantity_made as qty, lpi.unit_made as unit,
           mp.product_name as material_name, lpi.consumed_qty, lpi.consumed_unit
           FROM labour_production_items lpi
           JOIN labour_production lp ON lpi.production_id = lp.id
           JOIN labour l ON lp.labour_id = l.id
           JOIN products p ON lpi.product_id = p.id
           LEFT JOIN products mp ON lpi.material_product_id = mp.id
           WHERE lp.status = 'Active' AND lp.labour_id IN (
             SELECT id FROM labour WHERE labour_type = 'Piece Rate'
           )
           ORDER BY lp.production_date DESC""",
      );
      setState(() {
        _movements = rows.map((r) => Map<String, dynamic>.from(r)).toList();
        _loading = false;
        _hasResult = true;
      });
      return;
    }

    // Option 1 and Option 2 — product wise movement
    final pid = _selectedProductId!;
    String dateFilter = '';
    List<dynamic> dateParams = [];
    if (_selectedOption == 2 && _fromDate != null && _toDate != null) {
      dateFilter = 'AND movement_date BETWEEN ? AND ?';
      dateParams = [_fromDate!.toIso8601String(), _toDate!.toIso8601String()];
    }

    // Build movement type filter
    String typeFilter = '';
    if (_selectedMovementType == 'Purchase Only') {
      typeFilter = "AND movement_type IN ('Purchase','Manual Addition')";
    } else if (_selectedMovementType == 'Production Only') {
      typeFilter = "AND movement_type = 'Production'";
    } else if (_selectedMovementType == 'Consumed Only') {
      typeFilter = "AND movement_type = 'Consumed'";
    } else if (_selectedMovementType == 'Sold Only') {
      typeFilter = "AND movement_type = 'Sold'";
    } else if (_selectedMovementType == 'Reversed Only') {
      typeFilter = "AND movement_type IN ('Sold Reversed','Consumed Reversed','Production Reversed')";
    }

    // Get stock_in movements
    final stockRows = await db.rawQuery(
      "SELECT movement_date, movement_type, quantity, reference FROM stock_in WHERE product_id=? AND movement_type != 'Sold' $dateFilter $typeFilter ORDER BY movement_date ASC",
      [pid, ...dateParams],
    );

    // Get sold movements from invoice_items
    List<Map<String, dynamic>> soldRows = [];
    if (_selectedMovementType == 'All Types' || _selectedMovementType == 'Sold Only') {
      String soldDateFilter = '';
      List<dynamic> soldDateParams = [pid];
      if (_selectedOption == 2 && _fromDate != null && _toDate != null) {
        soldDateFilter = 'AND i.invoice_date BETWEEN ? AND ?';
        soldDateParams.addAll([_fromDate!.toIso8601String(), _toDate!.toIso8601String()]);
      }
      soldRows = await db.rawQuery(
        "SELECT i.invoice_date as movement_date, 'Sold' as movement_type, -ii.quantity as quantity, i.invoice_number as reference FROM invoice_items ii JOIN invoices i ON ii.invoice_id=i.id WHERE ii.product_id=? AND i.status!='Cancelled' $soldDateFilter ORDER BY i.invoice_date ASC",
        soldDateParams,
      );
    }

    // Get consumed movements
    List<Map<String, dynamic>> consumedRows = [];
    if (_selectedMovementType == 'All Types' || _selectedMovementType == 'Consumed Only') {
      consumedRows = await db.rawQuery(
        "SELECT lp.production_date as movement_date, 'Consumed' as movement_type, -lpi.consumed_qty as quantity, l.name as reference FROM labour_production_items lpi JOIN labour_production lp ON lpi.production_id=lp.id JOIN labour l ON lp.labour_id=l.id WHERE lpi.material_product_id=? AND lp.status='Active' ORDER BY lp.production_date ASC",
        [pid],
      );
    }

    // Merge and sort all movements
    final allMovements = <Map<String, dynamic>>[];
    allMovements.addAll(stockRows.map((r) => Map<String, dynamic>.from(r)));
    allMovements.addAll(soldRows.map((r) => Map<String, dynamic>.from(r)));
    allMovements.addAll(consumedRows.map((r) => Map<String, dynamic>.from(r)));
    allMovements.sort((a, b) => (a['movement_date'] as String).compareTo(b['movement_date'] as String));

    // Calculate running balance
    double balance = 0;
    for (final m in allMovements) {
      balance += (m['quantity'] as num).toDouble();
      m['balance'] = balance;
    }
    _currentStock = balance;

    setState(() {
      _movements = allMovements;
      _loading = false;
      _hasResult = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Report'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Option selector
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [1, 2, 3, 4].map((opt) {
                  final labels = {1: 'Product Wise', 2: 'Date Range', 3: 'Production Only', 4: 'All Summary'};
                  final selected = _selectedOption == opt;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(labels[opt]!),
                      selected: selected,
                      onSelected: (_) => setState(() { _selectedOption = opt; _hasResult = false; }),
                      selectedColor: const Color(0xFF1976D2),
                      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Filters
          if (_selectedOption != 3 && _selectedOption != 4)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  DropdownButtonFormField<int>(
                    value: _selectedProductId,
                    decoration: const InputDecoration(labelText: 'Select Product', border: OutlineInputBorder(), isDense: true),
                    items: _products.map((p) => DropdownMenuItem<int>(
                      value: p['id'] as int,
                      child: Text(p['product_name'] as String),
                    )).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final p = _products.firstWhere((x) => x['id'] == v);
                      setState(() {
                        _selectedProductId = v;
                        _selectedProductName = p['product_name'] as String;
                        _selectedProductUnit = p['unit'] as String;
                      });
                    },
                  ),
                  if (_selectedOption == 2) ...[
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
                  ],
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedMovementType,
                    decoration: const InputDecoration(labelText: 'Movement Type', border: OutlineInputBorder(), isDense: true),
                    items: _movementTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => _selectedMovementType = v ?? 'All Types'),
                  ),
                ],
              ),
            ),
          if (_selectedOption == 4)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Switch(
                    value: _showLowStockOnly,
                    onChanged: (v) => setState(() => _showLowStockOnly = v),
                    activeColor: const Color(0xFF1976D2),
                  ),
                  const Text('Show Low Stock Only'),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loadReport,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), foregroundColor: Colors.white),
                child: const Text('VIEW REPORT'),
              ),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_hasResult)
            Expanded(child: _buildResult()),
        ],
      ),
    );
  }

  Widget _buildResult() {
    if (_selectedOption == 4) return _buildAllSummary();
    if (_selectedOption == 3) return _buildProductionReport();
    return _buildMovementTable();
  }

  Widget _buildMovementTable() {
    if (_movements.isEmpty) {
      return const Center(child: Text('No movements found.'));
    }
    return Column(
      children: [
        Container(
          color: Colors.teal[50],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$_selectedProductName — Current Stock', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${_formatNum(_currentStock)} $_selectedProductUnit', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: Table(
              border: TableBorder.all(color: Colors.grey[300]!),
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(1.5),
                4: FlexColumnWidth(1.5),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.teal[700]),
                  children: ['Date', 'Type', 'Reference', 'Qty', 'Balance'].map((h) =>
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(h, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    )
                  ).toList(),
                ),
                ..._movements.map((m) {
                  final qty = (m['quantity'] as num).toDouble();
                  final bal = (m['balance'] as num).toDouble();
                  final isIn = qty > 0;
                  return TableRow(children: [
                    Padding(padding: const EdgeInsets.all(6), child: Text(m['movement_date'].toString().substring(0, 10), style: const TextStyle(fontSize: 11))),
                    Padding(padding: const EdgeInsets.all(6), child: Text(m['movement_type'].toString(), style: const TextStyle(fontSize: 11))),
                    Padding(padding: const EdgeInsets.all(6), child: Text(m['reference']?.toString() ?? '-', style: const TextStyle(fontSize: 11))),
                    Padding(padding: const EdgeInsets.all(6), child: Text('${isIn ? '+' : ''}${_formatNum(qty)}', style: TextStyle(fontSize: 11, color: isIn ? Colors.green[700] : Colors.red[700], fontWeight: FontWeight.bold))),
                    Padding(padding: const EdgeInsets.all(6), child: Text(_formatNum(bal), style: const TextStyle(fontSize: 11))),
                  ]);
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductionReport() {
    if (_movements.isEmpty) {
      return const Center(child: Text('No production entries found.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1.5),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(2),
          3: FlexColumnWidth(1.5),
          4: FlexColumnWidth(2),
          5: FlexColumnWidth(1.5),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.indigo[700]),
            children: ['Date', 'Labour', 'Product Made', 'Qty', 'Material', 'Consumed'].map((h) =>
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(h, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
              )
            ).toList(),
          ),
          ..._movements.map((m) => TableRow(children: [
            Padding(padding: const EdgeInsets.all(6), child: Text(m['movement_date'].toString().substring(0, 10), style: const TextStyle(fontSize: 11))),
            Padding(padding: const EdgeInsets.all(6), child: Text(m['labour_name']?.toString() ?? '-', style: const TextStyle(fontSize: 11))),
            Padding(padding: const EdgeInsets.all(6), child: Text(m['product_name']?.toString() ?? '-', style: const TextStyle(fontSize: 11))),
            Padding(padding: const EdgeInsets.all(6), child: Text('${_formatNum((m['qty'] as num).toDouble())} ${m['unit'] ?? ''}', style: const TextStyle(fontSize: 11))),
            Padding(padding: const EdgeInsets.all(6), child: Text(m['material_name']?.toString() ?? '-', style: const TextStyle(fontSize: 11))),
            Padding(padding: const EdgeInsets.all(6), child: Text(m['consumed_qty'] != null ? '${_formatNum((m['consumed_qty'] as num).toDouble())} ${m['consumed_unit'] ?? ''}' : '-', style: const TextStyle(fontSize: 11))),
          ])),
        ],
      ),
    );
  }

  Widget _buildAllSummary() {
    final list = _showLowStockOnly
        ? _allProductsSummary.where((p) => p['status'] != 'OK').toList()
        : _allProductsSummary;
    if (list.isEmpty) {
      return const Center(child: Text('No products found.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(2.5),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.5),
          3: FlexColumnWidth(1.5),
          4: FlexColumnWidth(1.5),
          5: FlexColumnWidth(1.2),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.teal[700]),
            children: ['Product', 'Unit', 'Total IN', 'Total OUT', 'Current', 'Status'].map((h) =>
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(h, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
              )
            ).toList(),
          ),
          ...list.map((p) {
            final status = p['status'] as String;
            final statusColor = status == 'OK' ? Colors.green[700]! : status == 'LOW' ? Colors.orange[700]! : Colors.red[700]!;
            return TableRow(children: [
              Padding(padding: const EdgeInsets.all(6), child: Text(p['product_name'].toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              Padding(padding: const EdgeInsets.all(6), child: Text(p['unit'].toString(), style: const TextStyle(fontSize: 11))),
              Padding(padding: const EdgeInsets.all(6), child: Text(_formatNum((p['total_in'] as num).toDouble()), style: TextStyle(fontSize: 11, color: Colors.green[700]))),
              Padding(padding: const EdgeInsets.all(6), child: Text(_formatNum((p['total_out'] as num).toDouble()), style: TextStyle(fontSize: 11, color: Colors.red[700]))),
              Padding(padding: const EdgeInsets.all(6), child: Text(_formatNum((p['current'] as num).toDouble()), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              Padding(padding: const EdgeInsets.all(6), child: Text(status, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold))),
            ]);
          }),
        ],
      ),
    );
  }
}
