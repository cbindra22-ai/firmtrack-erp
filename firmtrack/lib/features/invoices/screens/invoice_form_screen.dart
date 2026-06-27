import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';

class InvoiceFormScreen extends StatefulWidget {
  const InvoiceFormScreen({super.key});

  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _products = [];
  int? _selectedCustomerId;
  Map<String, dynamic>? _selectedCustomer;
  DateTime _invoiceDate = DateTime.now();
  final List<Map<String, dynamic>> _lineItems = [];
  bool _isSaving = false;
  bool _applyAdvance = false;
  double _customerAdvance = 0.0;
  String _notes = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = await DatabaseHelper.instance.database;
    final customers = await db.query('customers', orderBy: 'name ASC');
    final products = await db.query('products', orderBy: 'product_name ASC');
    setState(() {
      _customers = customers;
      _products = products;
    });
  }

  Future<String> _generateInvoiceNumber() async {
    final db = await DatabaseHelper.instance.database;
    final company = await db.query('company', limit: 1);
    String prefix = 'INV';
    if (company.isNotEmpty) {
      prefix = (company.first['invoice_prefix'] ?? 'INV').toString();
    }
    final count = await db.rawQuery('SELECT COUNT(*) as cnt FROM invoices');
    final next = ((count.first['cnt'] as int?) ?? 0) + 1;
    return '$prefix-${next.toString().padLeft(3, '0')}';
  }

  void _onCustomerChanged(int? customerId) {
    setState(() {
      _selectedCustomerId = customerId;
      _selectedCustomer = customerId != null
          ? _customers.firstWhere((c) => c['id'] == customerId)
          : null;
      _customerAdvance = 0.0;
      _applyAdvance = false;
    });
  }

  void _addLineItem() {
    setState(() {
      _lineItems.add({
        'product_id': null,
        'product_name': '',
        'quantity': 1.0,
        'rate': 0.0,
        'amount': 0.0,
        'available_stock': 0.0,
        'unit': '',
      });
    });
  }

  void _removeLineItem(int index) {
    setState(() => _lineItems.removeAt(index));
  }

  Future<void> _onProductSelected(int index, Map<String, dynamic>? product) async {
    if (product == null) return;
    final db = await DatabaseHelper.instance.database;
    final stockResult = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN movement_type IN ('Purchase','Opening Stock','Manual Addition','Production','Sold Reversed','Consumed Reversed')
        THEN quantity ELSE -quantity END), 0) as stock
      FROM stock_in WHERE product_id = ?
    ''', [product['id']]);
    final stock = ((stockResult.first['stock'] as num?) ?? 0.0).toDouble();
    setState(() {
      _lineItems[index]['product_id'] = product['id'];
      _lineItems[index]['product_name'] = product['product_name'];
      _lineItems[index]['rate'] = 0.0;
      _lineItems[index]['available_stock'] = stock;
      _lineItems[index]['amount'] =
          _lineItems[index]['quantity'] * _lineItems[index]['rate'];
    });
  }

  void _updateQuantity(int index, double qty) {
    setState(() {
      _lineItems[index]['quantity'] = qty;
      _lineItems[index]['amount'] = qty * (_lineItems[index]['rate'] as double);
    });
  }

  void _updateRate(int index, double rate) {
    setState(() {
      _lineItems[index]['rate'] = rate;
      _lineItems[index]['amount'] = (_lineItems[index]['quantity'] as double) * rate;
    });
  }

  double get _subtotal =>
      _lineItems.fold(0.0, (sum, item) => sum + (item['amount'] as double));

  double get _advanceApplied =>
      _applyAdvance ? (_customerAdvance > _subtotal ? _subtotal : _customerAdvance) : 0.0;

  double get _grandTotal => _subtotal - _advanceApplied;

  String? _validateItems() {
    if (_lineItems.isEmpty) return 'Add at least one product';
    for (final item in _lineItems) {
      if (item['product_id'] == null) return 'Select product for all line items';
      if ((item['quantity'] as double) <= 0) return 'Quantity must be greater than 0';
      if ((item['quantity'] as double) > (item['available_stock'] as double)) {
        return 'Insufficient stock for ${item['product_name']} '
            '(Available: ${item['available_stock']}, Requested: ${item['quantity']})';
      }
    }
    // Check duplicate products
    final ids = _lineItems.map((e) => e['product_id']).toList();
    if (ids.toSet().length != ids.length) return 'Duplicate products in line items';
    return null;
  }

  Future<void> _saveInvoice() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final itemError = _validateItems();
    if (itemError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(itemError)));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final db = await DatabaseHelper.instance.database;
      final invoiceNumber = await _generateInvoiceNumber();
      final now = DateTime.now().toIso8601String();
      final dateStr = _invoiceDate.toIso8601String().substring(0, 10);
      final advanceApplied = _advanceApplied;
      final balanceAmount = _grandTotal;

      await db.transaction((txn) async {
        // Insert invoice
        final invoiceId = await txn.insert('invoices', {
          'invoice_number': invoiceNumber,
          'customer_id': _selectedCustomer!['id'],
          'invoice_date': dateStr,
          'total_amount': _subtotal,
          'advance_used': advanceApplied,
          'balance': balanceAmount,
          'status': balanceAmount <= 0 ? 'Paid' : 'Unpaid',
          'notes': _notes,
          'created_at': now,
        });

        // Insert line items + stock OUT
        for (final item in _lineItems) {
          await txn.insert('invoice_items', {
            'invoice_id': invoiceId,
            'product_id': item['product_id'],
            'quantity': item['quantity'],
            'unit': item['unit'],
            'rate': item['rate'],
            'amount': item['amount'],
          });

          await txn.insert('stock_in', {
            'product_id': item['product_id'],
            'quantity': item['quantity'],
            'movement_type': 'Sold',
            'unit': item['unit'],
            'reference': invoiceNumber,
            'movement_date': dateStr,
            'created_at': now,
          });
        }

        // Deduct advance from customer if applied
        // advance is runtime calculated - no column to update
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invoice $invoiceNumber saved successfully')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving invoice: $e')));
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Invoice'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Customer
            DropdownButtonFormField<int>(
              value: _selectedCustomerId,
              decoration: const InputDecoration(
                labelText: 'Customer *',
                border: OutlineInputBorder(),
              ),
              items: _customers
                  .map((c) => DropdownMenuItem<int>(
                        value: c['id'] as int,
                        child: Text(c['name'].toString()),
                      ))
                  .toList(),
              onChanged: _onCustomerChanged,
              validator: (v) => v == null ? 'Select a customer' : null,
            ),
            const SizedBox(height: 12),

            // Advance info
            if (_selectedCustomer != null && _customerAdvance > 0)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Customer has advance: ₹${_customerAdvance.toStringAsFixed(2)}'),
                    ),
                    Switch(
                      value: _applyAdvance,
                      onChanged: (v) => setState(() => _applyAdvance = v),
                      activeColor: const Color(0xFF1976D2),
                    ),
                    const Text('Apply'),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Invoice Date
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Invoice Date *',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  '${_invoiceDate.day.toString().padLeft(2, '0')}/'
                  '${_invoiceDate.month.toString().padLeft(2, '0')}/'
                  '${_invoiceDate.year}',
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Line Items Header
            Row(
              children: [
                const Text('Products',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addLineItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Product'),
                ),
              ],
            ),
            const Divider(),

            // Line Items
            ..._lineItems.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Item ${i + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeLineItem(i),
                          ),
                        ],
                      ),
                      DropdownButtonFormField<int>(
                        value: item['product_id'] as int?,
                        decoration: const InputDecoration(
                          labelText: 'Product *',
                          border: OutlineInputBorder(),
                        ),
                        items: _products
                            .map((p) => DropdownMenuItem<int>(
                                  value: p['id'] as int,
                                  child: Text(p['product_name'].toString()),
                                ))
                            .toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          final product = _products.firstWhere((p) => p['id'] == id);
                          _onProductSelected(i, product);
                        },
                      ),
                      if (item['product_id'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Available Stock: ${(item['available_stock'] as double).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: (item['available_stock'] as double) > 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: item['quantity'].toString(),
                              decoration: const InputDecoration(
                                labelText: 'Qty *',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) =>
                                  _updateQuantity(i, double.tryParse(v) ?? 0),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: item['rate'].toString(),
                              decoration: const InputDecoration(
                                labelText: 'Rate ₹ *',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) =>
                                  _updateRate(i, double.tryParse(v) ?? 0),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Amount',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                '₹${(item['amount'] as double).toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

            if (_lineItems.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text('No products added yet')),
              ),

            const SizedBox(height: 12),

            // Notes
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onSaved: (v) => _notes = v ?? '',
            ),
            const SizedBox(height: 16),

            // Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal'),
                      Text('₹${_subtotal.toStringAsFixed(2)}'),
                    ],
                  ),
                  if (_applyAdvance && _advanceApplied > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Advance Applied',
                            style: TextStyle(color: Colors.blue)),
                        Text('- ₹${_advanceApplied.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.blue)),
                      ],
                    ),
                  ],
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Grand Total',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('₹${_grandTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Save Button
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveInvoice,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Invoice', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
