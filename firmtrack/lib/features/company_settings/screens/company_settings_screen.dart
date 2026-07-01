import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/database/database_helper.dart';

class CompanySettingsScreen extends StatefulWidget {
  final bool isFirstSetup;

  const CompanySettingsScreen({super.key, this.isFirstSetup = false});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _prefixController = TextEditingController();

  bool _isLoading = false;
  bool _isFetching = true;
  int? _existingId;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  // ─── Load existing company data if already saved ───────────────────────────
  Future<void> _loadExistingData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query('company', limit: 1);

      if (result.isNotEmpty) {
        final row = result.first;
        setState(() {
          _existingId = row['id'] as int?;
          _nameController.text = (row['company_name'] as String?) ?? '';
          _phoneController.text = (row['phone'] as String?) ?? '';
          _addressController.text = (row['address'] as String?) ?? '';
          _prefixController.text = (row['invoice_prefix'] as String?) ?? 'INV';
        });
      } else {
        _prefixController.text = 'INV';
      }
    } catch (e) {
      debugPrint('Error loading company data: $e');
    } finally {
      setState(() => _isFetching = false);
    }
  }

  // ─── Save company data ─────────────────────────────────────────────────────
  Future<void> _saveCompany() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final db = await DatabaseHelper.instance.database;

      final data = {
        'company_name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'invoice_prefix': _prefixController.text.trim().toUpperCase(),
      };

      if (_existingId != null) {
        // Update existing
        await db.update(
          'company',
          data,
          where: 'id = ?',
          whereArgs: [_existingId],
        );
      } else {
        // Insert new
        data['created_at'] = DateTime.now().toIso8601String();
        await db.insert('company', data);
      }

      if (!mounted) return;

      if (widget.isFirstSetup) {
        // First time → go to real Dashboard
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/dashboard',
          (route) => false,
        );
      } else {
        // Editing → go back
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Company settings saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error saving company: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isFirstSetup ? 'Setup Your Company' : 'Company Settings',
        ),
        automaticallyImplyLeading: !widget.isFirstSetup,
      ),
      body: _isFetching
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header info for first setup
                    if (widget.isFirstSetup) ...[
                      const Icon(
                        Icons.business,
                        size: 56,
                        color: Color(0xFF1565C0),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Welcome to FirmTrack ERP',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Set up your company details to get started.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Company Name
                    _buildLabel('Company Name *'),
                    TextFormField(
                      controller: _nameController,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Sharma Enterprises',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Company Name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Phone
                    _buildLabel('Phone Number'),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        hintText: 'e.g. 9876543210',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          if (value.trim().length != 10) {
                            return 'Phone number must be 10 digits';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Address
                    _buildLabel('Address'),
                    TextFormField(
                      controller: _addressController,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'e.g. 12 MG Road, Mumbai - 400001',
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.location_on_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Invoice Prefix
                    _buildLabel('Invoice Prefix *'),
                    TextFormField(
                      controller: _prefixController,
                      maxLength: 10,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: 'e.g. INV',
                        prefixIcon: Icon(Icons.tag_outlined),
                        helperText:
                            'Invoice numbers will look like: INV-0001',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Invoice Prefix is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveCompany,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                widget.isFirstSetup
                                    ? 'Save & Continue'
                                    : 'Save Changes',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}