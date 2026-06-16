import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';

class StockListScreen extends StatefulWidget {
  const StockListScreen({super.key});

  @override
  State<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends State<StockListScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _stockData = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStock() async {
    setState(() => _isLoading = true);
    try {
      final db = await _db.database;
      final products = await db.rawQuery('''
        SELECT
          p.id,
          p.product_name,
          p.product_code,
          p.unit,
          p.min_stock_level,
          COALESCE((
            SELECT SUM(s.quantity)
            FROM stock_in s
            WHERE s.product_id = p.id
          ), 0)
          -
          COALESCE((
            SELECT SUM(lpi.consumed_qty)
            FROM labour_production_items lpi
            JOIN labour_production lp ON lpi.production_id = lp.id
            WHERE lpi.material_product_id = p.id
              AND lp.status = 'Active'
          ), 0)
          -
          COALESCE((
            SELECT SUM(ii.quantity)
            FROM invoice_items ii
            JOIN invoices i ON ii.invoice_id = i.id
            WHERE ii.product_id = p.id
              AND i.status != 'Cancelled'
          ), 0)
          AS current_stock
        FROM products p
        ORDER BY p.product_name ASC
      ''');

      setState(() {
        _stockData = List<Map<String, dynamic>>.from(products);
        _filtered = _stockData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load stock data'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = _stockData;
      } else {
        _filtered = _stockData.where((item) {
          final name = (item['product_name'] ?? '').toLowerCase();
          final code = (item['product_code'] ?? '').toLowerCase();
          return name.contains(query.toLowerCase()) ||
              code.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  bool _isLowStock(Map<String, dynamic> item) {
    final current = (item['current_stock'] as num?)?.toDouble() ?? 0.0;
    final min = (item['min_stock_level'] as num?)?.toDouble() ?? 0.0;
    return min > 0 && current < min;
  }

  String _formatQty(dynamic value) {
    final d = (value as num?)?.toDouble() ?? 0.0;
    if (d == d.truncateToDouble()) return d.toStringAsFixed(0);
    return d.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock / Inventory'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStock,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search product...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              ),
            ),
          ),
          if (!_isLoading && _stockData.isNotEmpty)
            Builder(builder: (_) {
              final lowCount = _stockData.where(_isLowStock).length;
              if (lowCount == 0) return const SizedBox.shrink();
              return Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '$lowCount product(s) below minimum stock level',
                      style:
                          const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 4),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No products found'
                                  : 'No products added yet',
                              style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadStock,
                        child: ListView.builder(
                          itemCount: _filtered.length,
                          padding: const EdgeInsets.only(bottom: 80),
                          itemBuilder: (context, index) {
                            final item = _filtered[index];
                            final lowStock = _isLowStock(item);
                            final currentStock =
                                (item['current_stock'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                            final minStock =
                                (item['min_stock_level'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: lowStock
                                    ? BorderSide(
                                        color: Colors.red.shade300,
                                        width: 1.5)
                                    : BorderSide.none,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: lowStock
                                      ? Colors.red.shade100
                                      : Colors.teal.shade50,
                                  child: Icon(
                                    lowStock
                                        ? Icons.warning_amber_rounded
                                        : Icons.inventory_2_outlined,
                                    color: lowStock
                                        ? Colors.red
                                        : Colors.teal,
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  item['product_name'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if ((item['product_code'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Text(
                                        'Code: ${item['product_code']}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600),
                                      ),
                                    if (minStock > 0)
                                      Text(
                                        'Min: ${_formatQty(minStock)} ${item['unit'] ?? ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: lowStock
                                              ? Colors.red.shade700
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _formatQty(currentStock),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: lowStock
                                            ? Colors.red
                                            : Colors.teal.shade700,
                                      ),
                                    ),
                                    Text(
                                      item['unit'] ?? '',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600),
                                    ),
                                    if (lowStock)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'LOW',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.pushNamed(context, '/stock-in');
          _loadStock();
        },
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            const Text('Add Stock', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
