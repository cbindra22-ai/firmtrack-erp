import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/database/database_helper.dart';

class LabourFormScreen extends StatefulWidget {
  const LabourFormScreen({super.key});

  @override
  State<LabourFormScreen> createState() => _LabourFormScreenState();
}

class _LabourFormScreenState extends State<LabourFormScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _wageRateCtrl = TextEditingController();
  final TextEditingController _joinDateCtrl = TextEditingController();

  String _labourType = 'Daily Wage';
  bool _isSaving = false;
  bool _isEditMode = false;
  int? _editId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is Map<String, dynamic> && !_isEditMode) {
      _isEditMode = true;
      _editId = args['id'] as int;
      _nameCtrl.text = args['name'] as String? ?? '';
      _phoneCtrl.text = args['phone'] as String? ?? '';
      _addressCtrl.text = args['address'] as String? ?? '';
      _labourType = args['labour_type'] as String? ?? 'Daily Wage';
      _wageRateCtrl.text =
          args['daily_wage_rate'] != null ? args['daily_wage_rate'].toString() : '';
      _joinDateCtrl.text = args['join_date'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _wageRateCtrl.dispose();
    _joinDateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickJoinDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) {
      _joinDateCtrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final data = {
      'name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'labour_type': _labourType,
      'daily_wage_rate': _labourType == 'Daily Wage' && _wageRateCtrl.text.trim().isNotEmpty
          ? double.tryParse(_wageRateCtrl.text.trim())
          : null,
      'join_date': _joinDateCtrl.text.trim().isEmpty ? null : _joinDateCtrl.text.trim(),
    };

    try {
      final db = await _db.database;
      if (_isEditMode && _editId != null) {
        await db.update('labour', data, where: 'id = ?', whereArgs: [_editId]);
      } else {
        await db.insert('labour', data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode ? 'Labour updated' : 'Labour added'),
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
              backgroundColor: Colors.red),
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
        title: Text(_isEditMode ? 'Edit Labour' : 'Add Labour'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Name is required';
                  if (v.trim().length > 100) return 'Max 100 characters';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Phone
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty && v.trim().length != 10) {
                    return 'Phone must be 10 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Address
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 14),

              // Labour Type
              const Text('Labour Type *',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: const Text('Daily Wage'),
                      subtitle: const Text('Paid by days worked'),
                      value: 'Daily Wage',
                      groupValue: _labourType,
                      onChanged: (v) => setState(() => _labourType = v!),
                      activeColor: Colors.indigo,
                    ),
                    const Divider(height: 1),
                    RadioListTile<String>(
                      title: const Text('Piece Rate'),
                      subtitle: const Text('Paid by quantity produced'),
                      value: 'Piece Rate',
                      groupValue: _labourType,
                      onChanged: (v) => setState(() => _labourType = v!),
                      activeColor: Colors.indigo,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Daily Wage Rate — only for Daily Wage
              if (_labourType == 'Daily Wage') ...[
                TextFormField(
                  controller: _wageRateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Daily Wage Rate (₹) *',
                    border: OutlineInputBorder(),
                    prefixText: '₹ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
                  ],
                  validator: (v) {
                    if (_labourType != 'Daily Wage') return null;
                    if (v == null || v.trim().isEmpty) return 'Daily wage rate is required';
                    final val = double.tryParse(v.trim());
                    if (val == null || val <= 0) return 'Enter a valid rate > 0';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
              ],

              // Join Date
              TextFormField(
                controller: _joinDateCtrl,
                readOnly: true,
                onTap: _pickJoinDate,
                decoration: InputDecoration(
                  labelText: 'Join Date',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                  hintText: 'YYYY-MM-DD',
                  helperText: _joinDateCtrl.text.isNotEmpty
                      ? null
                      : 'Optional',
                ),
              ),
              const SizedBox(height: 28),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(_isEditMode ? 'Update Labour' : 'Add Labour',
                          style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
