import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import 'package:intl/intl.dart';

class PieceRateCardScreen extends StatefulWidget {
  const PieceRateCardScreen({super.key});
  @override
  State<PieceRateCardScreen> createState() => _PieceRateCardScreenState();
}

class _PieceRateCardScreenState extends State<PieceRateCardScreen> {
  Map<String, dynamic>? _labour;
  List<Map<String, dynamic>> _rates = [];
  bool _loading = true;
  static const Color _primary = Color(0xFF3949AB);

  String _fmtAmt(double v) => NumberFormat('##,##,##0.00','en_IN').format(v);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_labour == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) { _labour = args; _loadRates(); }
    }
  }

  Future<void> _loadRates() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.instance.database;
    final lid = _labour!['id'] as int;
    final rows = await db.rawQuery('''
      SELECT lpr.id, lpr.rate_per_unit, lpr.unit,
             p.product_name, p.id AS product_id
      FROM labour_piece_rates lpr
      JOIN products p ON p.id = lpr.product_id
      WHERE lpr.labour_id = ?
      ORDER BY p.product_name ASC
    ''', [lid]);
    if (mounted) setState(() { _rates = rows; _loading = false; });
  }

  Future<void> _deleteRate(int id) async {
    final ok = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Rate'),
        content: const Text('Remove this piece rate?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ]));
    if (ok == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('labour_piece_rates', where: 'id = ?', whereArgs: [id]);
      _loadRates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final labour = _labour;
    if (labour == null) return const Scaffold(body: Center(child: Text('No labour selected.')));
    final labourName = labour['name'] as String? ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _primary, foregroundColor: Colors.white,
        title: Text('${labourName} - Piece Rates'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rates.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.sell_outlined, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No piece rates set yet',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text('Tap + Add Rate to set product rates',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rates.length,
                  itemBuilder: (_, i) {
                    final r = _rates[i];
                    final productName = r['product_name'] as String? ?? '';
                    final unit = r['unit'] as String? ?? '';
                    final rate = (r['rate_per_unit'] as num?)?.toDouble() ?? 0.0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE8EAF6),
                          child: Icon(Icons.sell_outlined, color: _primary, size: 20)),
                        title: Text(productName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Per ${unit}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('Rs.${_fmtAmt(rate)}',
                            style: const TextStyle(fontWeight: FontWeight.bold,
                                color: _primary, fontSize: 14)),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
                            onPressed: () async {
                              await Navigator.pushNamed(context, '/piece-rate-form',
                                arguments: {'labour': labour, 'rate': r});
                              _loadRates();
                            }),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            onPressed: () => _deleteRate(r['id'] as int)),
                        ]),
                      ));
                  }),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Rate', style: TextStyle(color: Colors.white)),
        onPressed: () async {
          await Navigator.pushNamed(context, '/piece-rate-form',
            arguments: {'labour': labour, 'rate': null});
          _loadRates();
        }),
    );
  }
}

class PieceRateFormScreen extends StatefulWidget {
  const PieceRateFormScreen({super.key});
  @override
  State<PieceRateFormScreen> createState() => _PieceRateFormScreenState();
}

class _PieceRateFormScreenState extends State<PieceRateFormScreen> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic>? _labour;
  Map<String, dynamic>? _existingRate;
  List<Map<String, dynamic>> _products = [];
  int? _selectedProductId;
  String _selectedUnit = '';
  final _rateCtrl = TextEditingController();
  bool _isSaving = false;
  bool _loaded = false;
  static const Color _primary = Color(0xFF3949AB);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _labour = args['labour'] as Map<String, dynamic>?;
        _existingRate = args['rate'] as Map<String, dynamic>?;
        if (_existingRate != null) {
          _rateCtrl.text = (_existingRate!['rate_per_unit'] as num?)?.toString() ?? '';
          _selectedUnit = (_existingRate!['unit'] as String?) ?? '';
          _selectedProductId = _existingRate!['product_id'] as int?;
        }
      }
      _loadProducts();
    }
  }

  Future<void> _loadProducts() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('products', orderBy: 'product_name ASC');
    if (mounted) setState(() => _products = rows);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a product'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _isSaving = true);
    final db = await DatabaseHelper.instance.database;
    final labourId = _labour!['id'] as int;
    final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
    final product = _products.firstWhere((p) => p['id'] == _selectedProductId);
    final unit = _selectedUnit.isNotEmpty ? _selectedUnit : (product['unit'] as String? ?? '');
    final now = DateTime.now().toIso8601String();
    try {
      if (_existingRate != null) {
        await db.update('labour_piece_rates',
          {'product_id': _selectedProductId, 'rate_per_unit': rate, 'unit': unit},
          where: 'id = ?', whereArgs: [_existingRate!['id']]);
      } else {
        final existing = await db.query('labour_piece_rates',
          where: 'labour_id = ? AND product_id = ?',
          whereArgs: [labourId, _selectedProductId]);
        if (existing.isNotEmpty) {
          setState(() => _isSaving = false);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Rate for this product already exists. Edit it instead.'),
            backgroundColor: Colors.orange));
          return;
        }
        await db.insert('labour_piece_rates', {
          'labour_id': labourId,
          'product_id': _selectedProductId,
          'rate_per_unit': rate,
          'unit': unit,
          'created_at': now,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Piece rate saved'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to save. Please try again.'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = _existingRate != null;
    final labourName = _labour != null ? _labour!['name'] as String? ?? '' : '';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _primary, foregroundColor: Colors.white,
        title: Text(isEdit ? 'Edit Piece Rate' : 'Add Piece Rate'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_labour != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _primary.withValues(alpha: 0.3))),
                  child: Text('Labour: ${labourName}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: _primary)),
                ),
              const Text('Product *',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _selectedProductId,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: 'Select product',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: Colors.white),
                items: _products.map((p) => DropdownMenuItem<int>(
                  value: p['id'] as int,
                  child: Text(p['product_name'] as String? ?? ''))).toList(),
                onChanged: isEdit ? null : (val) {
                  setState(() {
                    _selectedProductId = val;
                    if (val != null) {
                      final prod = _products.firstWhere((p) => p['id'] == val);
                      _selectedUnit = prod['unit'] as String? ?? '';
                    }
                  });
                },
                validator: (v) => v == null ? 'Please select a product' : null,
              ),
              const SizedBox(height: 16),
              if (_selectedUnit.isNotEmpty) ...[
                const Text('Unit',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300)),
                  child: Text(_selectedUnit,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 16),
              ],
              const Text('Rate per Unit (Rs.) *',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: 'e.g. 2.00',
                  prefixText: 'Rs. ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: Colors.white),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Rate is required';
                  final d = double.tryParse(v.trim());
                  if (d == null || d <= 0) return 'Enter a valid rate greater than 0';
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(isEdit ? 'Update Rate' : 'Save Rate',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { _rateCtrl.dispose(); super.dispose(); }
}
