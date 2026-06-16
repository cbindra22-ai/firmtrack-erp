import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';

class StockInScreen extends StatefulWidget {
  const StockInScreen({super.key});

  @override
  State<StockInScreen> createState() => _StockInScreenState();
}

class _StockInScreenState extends State<StockInScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic>? _selectedProduct;
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  String _selectedMovementType = 'Purchase';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isLoadingProducts = true;

  final List<String> _movementTypes = [
    'Purchase',
    'Opening Stock',
    'Manual Addition',
  ];

  @override
  void initState() {
    super.initState();
    _dateController.text = DateFormat('dd MMM yyyy').format(_selectedDate);
    _loadProducts();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _referenceController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final db = await _db.database;
      final result = await db.query(
        'products',
        orderBy: 'product_name ASC',
      );
      setState(() {
        _products = List<Map<String, dynamic>>.from(result);
        _isLoadingProducts = false;
      });
    } catch (e) {
      setState(() => _isLoadingProducts = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load products'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('dd MMM yyyy').format(picked);
      });
    }
  }

  Future<void> _saveStockIn() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a product'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = await _db.database;
      final quantity = double.parse(_quantityController.text.trim());
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      await db.insert('stock_in', {
        'product_id': _selectedProduct!['id'],
        'movement_type': _selectedMovementType,
        'quantity': quantity,
        'unit': _selectedProduct!['unit'],
        'reference': _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        'movement_date': dateStr,
        'created_at': DateTime.now().toIso8601String(),
      });

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save stock entry'),
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
        title: const Text('Add Stock'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingProducts
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'No products found',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add products first from Products menu',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product Dropdown
                        const Text(
                          'Product *',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<Map<String, dynamic>>(
                          value: _selectedProduct,
                          hint: const Text('Select Product'),
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                          items: _products.map((product) {
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: product,
                              child: Text(
                                product['product_name'] ?? '',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedProduct = value);
                          },
                          validator: (value) {
                            if (value == null) return 'Please select a product';
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Show selected product unit
                        if (_selectedProduct != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    color: Colors.teal, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Unit: ${_selectedProduct!['unit'] ?? ''}',
                                  style: const TextStyle(
                                      color: Colors.teal,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),

                        if (_selectedProduct != null)
                          const SizedBox(height: 16),

                        // Movement Type
                        const Text(
                          'Movement Type *',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedMovementType,
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                          items: _movementTypes.map((type) {
                            return DropdownMenuItem<String>(
                              value: type,
                              child: Text(type),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(
                                () => _selectedMovementType = value!);
                          },
                        ),

                        const SizedBox(height: 16),

                        // Quantity
                        const Text(
                          'Quantity *',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _quantityController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            hintText: 'Enter quantity',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Quantity is required';
                            }
                            final qty = double.tryParse(value.trim());
                            if (qty == null) {
                              return 'Please enter a valid number';
                            }
                            if (qty <= 0) {
                              return 'Quantity must be greater than 0';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Date
                        const Text(
                          'Date *',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _dateController,
                          readOnly: true,
                          onTap: _pickDate,
                          decoration: InputDecoration(
                            hintText: 'Select date',
                            prefixIcon:
                                const Icon(Icons.calendar_today, size: 20),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Date is required';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Reference / Note
                        const Text(
                          'Reference / Supplier (Optional)',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _referenceController,
                          maxLength: 200,
                          decoration: InputDecoration(
                            hintText: 'Supplier name, note, etc.',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Save Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _saveStockIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Save Stock Entry',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
