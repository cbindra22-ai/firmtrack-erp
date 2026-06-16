import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import 'product_form_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filtered = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final db = await DatabaseHelper.instance.database;
    final result = await db.query('products', orderBy: 'name ASC');
    setState(() {
      _products = result;
      _filtered = result;
      _isLoading = false;
    });
  }

  void _onSearch(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? _products
          : _products.where((p) {
              return (p['name'] as String).toLowerCase().contains(q) ||
                  ((p['code'] ?? '') as String).toLowerCase().contains(q) ||
                  ((p['category'] ?? '') as String).toLowerCase().contains(q);
            }).toList();
    });
  }

  Future<void> _deleteProduct(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('products', where: 'id = ?', whereArgs: [id]);
      _loadProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$name" deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name, code, category...',
                hintStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white24,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        _products.isEmpty ? 'No products yet' : 'No results found',
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      if (_products.isEmpty) ...[
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const ProductFormScreen()));
                            _loadProducts();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add First Product'),
                        ),
                      ]
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadProducts,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    separatorBuilder: (a, b) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final p = _filtered[index];
                      final isLowStock = p['min_stock_level'] != null &&
                          (p['current_stock'] ?? 0) <= (p['min_stock_level'] ?? 0);
                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isLowStock
                                ? Colors.red.shade100
                                : const Color(0xFF1565C0).withValues(alpha: 0.1),
                            child: Icon(
                              Icons.inventory_2,
                              color: isLowStock ? Colors.red : const Color(0xFF1565C0),
                            ),
                          ),
                          title: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((p['code'] ?? '').toString().isNotEmpty)
                                Text('Code: ${p['code']}', style: const TextStyle(fontSize: 12)),
                              if ((p['category'] ?? '').toString().isNotEmpty)
                                Text('Category: ${p['category']}', style: const TextStyle(fontSize: 12)),
                              Text(
                                'Stock: ${p['current_stock'] ?? 0} ${p['unit'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isLowStock ? Colors.red : Colors.green.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProductFormScreen(product: p),
                                  ),
                                );
                                _loadProducts();
                              } else if (value == 'delete') {
                                await _deleteProduct(p['id'] as int, p['name'] as String);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ProductFormScreen()));
          _loadProducts();
        },
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
    );
  }
}
