import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';

class ProductionListScreen extends StatefulWidget {
  const ProductionListScreen({super.key});

  @override
  State<ProductionListScreen> createState() => _ProductionListScreenState();
}

class _ProductionListScreenState extends State<ProductionListScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    try {
      final database = await _db.database;
      final results = await database.rawQuery('''
        SELECT
          lp.id,
          lp.production_date,
          lp.total_earned,
          lp.status,
          lp.cancelled_at,
          l.name AS labour_name,
          (
            SELECT GROUP_CONCAT(p.product_name, ', ')
            FROM labour_production_items lpi
            JOIN products p ON lpi.product_id = p.id
            WHERE lpi.production_id = lp.id
          ) AS products_made
        FROM labour_production lp
        JOIN labour l ON lp.labour_id = l.id
        ORDER BY lp.production_date DESC, lp.created_at DESC
      ''');
      setState(() {
        _entries = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load production entries'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  String _formatAmount(double amount) {
    final formatter = NumberFormat('#,##,##0.00', 'en_IN');
    return '₹${formatter.format(amount)}';
  }

  Future<void> _cancelEntry(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Production Entry?'),
        content: const Text(
          'This will reverse all stock movements:\n'
          '• Raw material stock will be restored\n'
          '• Finished goods stock will be deducted\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final database = await _db.database;

      await database.transaction((txn) async {
        final productionId = entry['id'] as int;
        final now = DateTime.now().toIso8601String();

        final items = await txn.query(
          'labour_production_items',
          where: 'production_id = ?',
          whereArgs: [productionId],
        );

        for (final item in items) {
          final productId = item['product_id'] as int;
          final quantityMade = (item['quantity_made'] as num).toDouble();
          final unitMade = item['unit_made'] as String;
          final materialProductId = item['material_product_id'];
          final consumedQty = item['consumed_qty'];
          final consumedUnit = item['consumed_unit'];
          final productionDate = entry['production_date'] as String;

          await txn.insert('stock_in', {
            'product_id': productId,
            'movement_type': 'Production Reversed',
            'quantity': -quantityMade,
            'unit': unitMade,
            'reference': 'Production Cancelled',
            'labour_id': null,
            'production_id': productionId,
            'movement_date': productionDate,
            'created_at': now,
          });

          if (materialProductId != null && consumedQty != null) {
            await txn.insert('stock_in', {
              'product_id': materialProductId,
              'movement_type': 'Consumed Reversed',
              'quantity': (consumedQty as num).toDouble(),
              'unit': consumedUnit ?? '',
              'reference': 'Production Cancelled',
              'labour_id': null,
              'production_id': productionId,
              'movement_date': productionDate,
              'created_at': now,
            });
          }
        }

        await txn.update(
          'labour_production',
          {
            'status': 'Cancelled',
            'cancelled_at': now,
          },
          where: 'id = ?',
          whereArgs: [productionId],
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Production entry cancelled. Stock reversed.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await _loadEntries();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to cancel entry. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Production Entries'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(context, '/production-form');
          _loadEntries();
        },
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.precision_manufacturing_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No production entries yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add a production entry',
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadEntries,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      final isCancelled = entry['status'] == 'Cancelled';
                      final totalEarned =
                          (entry['total_earned'] as num?)?.toDouble() ?? 0.0;
                      final productsMade =
                          entry['products_made'] as String? ?? '—';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: isCancelled
                              ? const BorderSide(color: Colors.red, width: 1)
                              : BorderSide.none,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry['labour_name'] as String? ?? '—',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isCancelled
                                            ? Colors.grey[500]
                                            : Colors.black87,
                                        decoration: isCancelled
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isCancelled
                                          ? Colors.red[50]
                                          : Colors.green[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isCancelled
                                            ? Colors.red
                                            : Colors.green,
                                      ),
                                    ),
                                    child: Text(
                                      isCancelled ? 'Cancelled' : 'Active',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isCancelled
                                            ? Colors.red
                                            : Colors.green[700],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today,
                                      size: 13, color: Colors.grey[500]),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDate(
                                        entry['production_date'] as String),
                                    style: TextStyle(
                                        fontSize: 13, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.inventory_2_outlined,
                                      size: 13, color: Colors.grey[500]),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      productsMade,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700]),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Total Earned',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500]),
                                      ),
                                      Text(
                                        _formatAmount(totalEarned),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: isCancelled
                                              ? Colors.grey[400]
                                              : Colors.indigo[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!isCancelled)
                                    TextButton.icon(
                                      onPressed: () => _cancelEntry(entry),
                                      icon: const Icon(Icons.cancel_outlined,
                                          size: 16),
                                      label: const Text('Cancel'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                      ),
                                    ),
                                ],
                              ),
                              if (isCancelled &&
                                  entry['cancelled_at'] != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Cancelled on: ${_formatDate(entry['cancelled_at'] as String)}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.red),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
