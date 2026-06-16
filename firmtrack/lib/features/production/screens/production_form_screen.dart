import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';

class ProductionFormScreen extends StatefulWidget {
  const ProductionFormScreen({super.key});

  @override
  State<ProductionFormScreen> createState() => _ProductionFormScreenState();
}

class _ProductionFormScreenState extends State<ProductionFormScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Header fields
  int? _selectedLabourId;
  String? _selectedLabourName;
  DateTime _selectedDate = DateTime.now();

  // Lists
  List<Map<String, dynamic>> _pieceRateLabourList = [];
  List<Map<String, dynamic>> _allProducts = [];

  // Line items
  final List<_ProductionLineItem> _lineItems = [];

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final database = await _db.database;

      // Only Piece Rate labour
      final labourResult = await database.query(
        'labour',
        where: 'labour_type = ?',
        whereArgs: ['Piece Rate'],
        orderBy: 'name ASC',
      );

      // All products
      final productResult = await database.query(
        'products',
        orderBy: 'product_name ASC',
      );

      setState(() {
        _pieceRateLabourList = labourResult;
        _allProducts = productResult;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load data. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Get piece rate for a labour + product combination
  Future<double> _getPieceRate(int labourId, int productId) async {
    final database = await _db.database;
    final result = await database.query(
      'labour_piece_rates',
      where: 'labour_id = ? AND product_id = ?',
      whereArgs: [labourId, productId],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return (result.first['rate_per_unit'] as num).toDouble();
    }
    return 0.0;
  }

  // Get current stock for a product (runtime calculation per business rules)
  Future<double> _getCurrentStock(int productId) async {
    final database = await _db.database;

    // SUM from stock_in table
    final stockInResult = await database.rawQuery(
      'SELECT COALESCE(SUM(quantity), 0) AS total FROM stock_in WHERE product_id = ?',
      [productId],
    );
    final stockIn =
        (stockInResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // SUM consumed from active production
    final consumedResult = await database.rawQuery('''
      SELECT COALESCE(SUM(lpi.consumed_qty), 0) AS total
      FROM labour_production_items lpi
      JOIN labour_production lp ON lpi.production_id = lp.id
      WHERE lpi.material_product_id = ?
        AND lp.status = 'Active'
    ''', [productId]);
    final consumed =
        (consumedResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // SUM sold from non-cancelled invoices
    final soldResult = await database.rawQuery('''
      SELECT COALESCE(SUM(ii.quantity), 0) AS total
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE ii.product_id = ?
        AND i.status != 'Cancelled'
    ''', [productId]);
    final sold = (soldResult.first['total'] as num?)?.toDouble() ?? 0.0;

    return stockIn - consumed - sold;
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  double get _totalEarned {
    return _lineItems.fold(0.0, (sum, item) => sum + item.amount);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _addLineItem() {
    if (_selectedLabourId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a labour first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() {
      _lineItems.add(_ProductionLineItem());
    });
  }

  void _removeLineItem(int index) {
    setState(() {
      _lineItems.removeAt(index);
    });
  }

  Future<void> _onProductSelected(int index, int productId) async {
    if (_selectedLabourId == null) return;

    final product = _allProducts.firstWhere((p) => p['id'] == productId);
    final rate = await _getPieceRate(_selectedLabourId!, productId);

    setState(() {
      _lineItems[index].productId = productId;
      _lineItems[index].productName = product['product_name'] as String;
      _lineItems[index].unit = product['unit'] as String;
      _lineItems[index].rate = rate;
      _lineItems[index].rateController.text =
          rate > 0 ? rate.toStringAsFixed(2) : '';
      _lineItems[index]._recalculate();
    });
  }

  Future<void> _saveEntry() async {
    // Validation: labour
    if (_selectedLabourId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Labour is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validation: line items
    if (_lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one product line item'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate each line item
    for (int i = 0; i < _lineItems.length; i++) {
      final item = _lineItems[i];
      if (item.productId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Row ${i + 1}: Select a product'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (item.quantityMade <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Row ${i + 1}: Quantity made must be > 0'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (item.rate <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Row ${i + 1}: Rate must be > 0'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // If raw material selected, consumed qty must be > 0
      if (item.materialProductId != null && item.consumedQty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Row ${i + 1}: Consumed quantity must be > 0'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Stock check for raw materials
    for (int i = 0; i < _lineItems.length; i++) {
      final item = _lineItems[i];
      if (item.materialProductId != null && item.consumedQty > 0) {
        final available = await _getCurrentStock(item.materialProductId!);
        if (available < item.consumedQty) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Insufficient Stock'),
                  ],
                ),
                content: Text(
                  'Product: ${item.materialProductName ?? ''}\n'
                  'Available: ${available.toStringAsFixed(2)} ${item.materialUnit ?? ''}\n'
                  'Requested: ${item.consumedQty.toStringAsFixed(2)} ${item.materialUnit ?? ''}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }
    }

    // Save
    setState(() => _isSaving = true);

    try {
      final database = await _db.database;
      final dateStr =
          DateFormat('yyyy-MM-dd').format(_selectedDate);
      final now = DateTime.now().toIso8601String();
      final totalEarned = _totalEarned;

      await database.transaction((txn) async {
        // Step 1: Insert labour_production
        final productionId = await txn.insert('labour_production', {
          'labour_id': _selectedLabourId,
          'production_date': dateStr,
          'total_earned': totalEarned,
          'status': 'Active',
          'cancelled_at': null,
          'created_at': now,
        });

        // Step 2 & 3: Insert items + stock movements
        for (final item in _lineItems) {
          // Insert labour_production_items
          await txn.insert('labour_production_items', {
            'production_id': productionId,
            'product_id': item.productId,
            'quantity_made': item.quantityMade,
            'unit_made': item.unit,
            'rate': item.rate,
            'amount': item.amount,
            'material_product_id': item.materialProductId,
            'consumed_qty':
                item.materialProductId != null ? item.consumedQty : null,
            'consumed_unit':
                item.materialProductId != null ? item.materialUnit : null,
            'created_at': now,
          });

          // Auto stock IN: finished product (Production)
          await txn.insert('stock_in', {
            'product_id': item.productId,
            'movement_type': 'Production',
            'quantity': item.quantityMade,
            'unit': item.unit,
            'reference': _selectedLabourName ?? '',
            'labour_id': _selectedLabourId,
            'production_id': productionId,
            'movement_date': dateStr,
            'created_at': now,
          });

          // Auto stock OUT: raw material (Consumed) — negative qty
          if (item.materialProductId != null && item.consumedQty > 0) {
            await txn.insert('stock_in', {
              'product_id': item.materialProductId,
              'movement_type': 'Consumed',
              'quantity': -item.consumedQty,
              'unit': item.materialUnit ?? '',
              'reference': _selectedLabourName ?? '',
              'labour_id': _selectedLabourId,
              'production_id': productionId,
              'movement_date': dateStr,
              'created_at': now,
            });
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Production entry saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Production Entry'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── HEADER CARD ──
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Entry Details',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.indigo,
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Labour dropdown
                                const Text(
                                  'Labour *',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 6),
                                _pieceRateLabourList.isEmpty
                                    ? Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.orange[50],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: Colors.orange),
                                        ),
                                        child: const Text(
                                          'No Piece Rate labour found.\nAdd a Piece Rate labour first.',
                                          style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 13),
                                        ),
                                      )
                                    : DropdownButtonFormField<int>(
                                        value: _selectedLabourId,
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10),
                                          hintText: 'Select Labour',
                                        ),
                                        items: _pieceRateLabourList
                                            .map((l) =>
                                                DropdownMenuItem<int>(
                                                  value: l['id'] as int,
                                                  child: Text(
                                                      l['name'] as String),
                                                ))
                                            .toList(),
                                        onChanged: (val) {
                                          setState(() {
                                            _selectedLabourId = val;
                                            _selectedLabourName =
                                                _pieceRateLabourList
                                                    .firstWhere((l) =>
                                                        l['id'] == val)['name']
                                                    as String;
                                            // Reset line items on labour change
                                            _lineItems.clear();
                                          });
                                        },
                                      ),
                                const SizedBox(height: 14),

                                // Date picker
                                const Text(
                                  'Date *',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: _pickDate,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: Colors.grey[400]!),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.calendar_today,
                                            size: 16,
                                            color: Colors.indigo),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatDate(_selectedDate),
                                          style: const TextStyle(
                                              fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── LINE ITEMS ──
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Products Made',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.indigo,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _addLineItem,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Product'),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.indigo),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (_lineItems.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Center(
                              child: Text(
                                'No products added yet.\nTap "Add Product" to begin.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 13),
                              ),
                            ),
                          ),

                        // Line item cards
                        ...List.generate(_lineItems.length, (index) {
                          final item = _lineItems[index];
                          return _buildLineItemCard(index, item);
                        }),

                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),

                // ── FOOTER ──
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Total Earned',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            '₹${NumberFormat('#,##,##0.00', 'en_IN').format(_totalEarned)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveEntry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Save',
                                style: TextStyle(fontSize: 15)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLineItemCard(int index, _ProductionLineItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row header: Item number + delete
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Item ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.indigo,
                  ),
                ),
                IconButton(
                  onPressed: () => _removeLineItem(index),
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Product Made dropdown
            const Text('Product Made *',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              value: item.productId,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                hintText: 'Select product',
              ),
              items: _allProducts
                  .map((p) => DropdownMenuItem<int>(
                        value: p['id'] as int,
                        child: Text(p['product_name'] as String,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) _onProductSelected(index, val);
              },
            ),
            const SizedBox(height: 10),

            // Qty Made + Rate row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Qty Made *',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: item.qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          hintText: '0',
                          suffixText: item.unit,
                        ),
                        onChanged: (val) {
                          setState(() {
                            item.quantityMade =
                                double.tryParse(val) ?? 0.0;
                            item._recalculate();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Rate *',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: item.rateController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          hintText: '0.00',
                          prefixText: '₹',
                        ),
                        onChanged: (val) {
                          setState(() {
                            item.rate = double.tryParse(val) ?? 0.0;
                            item._recalculate();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Amount display
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Amount: ₹${NumberFormat('#,##,##0.00', 'en_IN').format(item.amount)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                  fontSize: 13,
                ),
              ),
            ),
            const Divider(height: 20),

            // Raw Material section
            const Text(
              'Raw Material Used (Optional)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 6),

            // Material product dropdown
            DropdownButtonFormField<int>(
              value: item.materialProductId,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                hintText: 'Select raw material (optional)',
              ),
              items: [
                const DropdownMenuItem<int>(
                  value: null,
                  child: Text('— None —'),
                ),
                ..._allProducts.map((p) => DropdownMenuItem<int>(
                      value: p['id'] as int,
                      child: Text(p['product_name'] as String,
                          overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (val) {
                setState(() {
                  item.materialProductId = val;
                  if (val != null) {
                    final product = _allProducts
                        .firstWhere((p) => p['id'] == val);
                    item.materialProductName =
                        product['product_name'] as String;
                    item.materialUnit = product['unit'] as String;
                  } else {
                    item.materialProductName = null;
                    item.materialUnit = null;
                    item.consumedQty = 0.0;
                    item.consumedQtyController.text = '';
                  }
                });
              },
            ),

            // Consumed qty — only shown if material selected
            if (item.materialProductId != null) ...[
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Consumed Qty *',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: item.consumedQtyController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      hintText: '0',
                      suffixText: item.materialUnit ?? '',
                    ),
                    onChanged: (val) {
                      setState(() {
                        item.consumedQty = double.tryParse(val) ?? 0.0;
                      });
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Line Item Model ──
class _ProductionLineItem {
  int? productId;
  String? productName;
  String unit = '';
  double quantityMade = 0.0;
  double rate = 0.0;
  double amount = 0.0;

  int? materialProductId;
  String? materialProductName;
  String? materialUnit;
  double consumedQty = 0.0;

  final TextEditingController qtyController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController consumedQtyController =
      TextEditingController();

  void _recalculate() {
    amount = quantityMade * rate;
  }

  void dispose() {
    qtyController.dispose();
    rateController.dispose();
    consumedQtyController.dispose();
  }
}
