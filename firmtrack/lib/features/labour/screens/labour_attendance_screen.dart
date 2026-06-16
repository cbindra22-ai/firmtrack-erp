import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';

class LabourAttendanceScreen extends StatefulWidget {
  const LabourAttendanceScreen({super.key});

  @override
  State<LabourAttendanceScreen> createState() => _LabourAttendanceScreenState();
}

class _LabourAttendanceScreenState extends State<LabourAttendanceScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<Map<String, dynamic>> _labourList = [];
  Map<String, dynamic>? _selectedLabour;
  List<Map<String, dynamic>> _attendanceList = [];

  final TextEditingController _dateCtrl = TextEditingController();
  String _selectedStatus = 'Present';
  bool _isLoading = false;
  bool _isSaving = false;
  int? _editAttendanceId;

  final List<String> _statusOptions = ['Present', 'Half Day', 'Absent'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateCtrl.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _loadDailyWageLabour();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDailyWageLabour() async {
    final db = await _db.database;
    final rows = await db.query(
      'labour',
      where: 'labour_type = ?',
      whereArgs: ['Daily Wage'],
      orderBy: 'name ASC',
    );
    setState(() => _labourList = rows);
  }

  Future<void> _loadAttendance(int labourId) async {
    setState(() => _isLoading = true);
    final db = await _db.database;
    final rows = await db.query(
      'labour_attendance',
      where: 'labour_id = ?',
      whereArgs: [labourId],
      orderBy: 'attendance_date DESC',
    );
    setState(() {
      _attendanceList = rows;
      _isLoading = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) {
      _dateCtrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  double _calcEarned(String status, double wageRate) {
    if (status == 'Present') return wageRate;
    if (status == 'Half Day') return wageRate / 2;
    return 0.0;
  }

  Future<void> _saveAttendance() async {
    if (_selectedLabour == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a labour'),
            backgroundColor: Colors.red),
      );
      return;
    }
    if (_dateCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a date'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final db = await _db.database;
      final int labourId = _selectedLabour!['id'] as int;
      final double wageRate =
          (_selectedLabour!['daily_wage_rate'] as num?)?.toDouble() ?? 0.0;
      final double earned = _calcEarned(_selectedStatus, wageRate);
      final String date = _dateCtrl.text.trim();

      if (_editAttendanceId != null) {
        // Edit existing
        await db.update(
          'labour_attendance',
          {
            'status': _selectedStatus,
            'earned_amount': earned,
          },
          where: 'id = ?',
          whereArgs: [_editAttendanceId],
        );
        setState(() => _editAttendanceId = null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Attendance updated'),
                backgroundColor: Colors.green),
          );
        }
      } else {
        // Check duplicate
        final existing = await db.query(
          'labour_attendance',
          where: 'labour_id = ? AND attendance_date = ?',
          whereArgs: [labourId, date],
        );
        if (existing.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Attendance already marked for this date'),
                  backgroundColor: Colors.red),
            );
          }
          setState(() => _isSaving = false);
          return;
        }

        await db.insert('labour_attendance', {
          'labour_id': labourId,
          'attendance_date': date,
          'status': _selectedStatus,
          'earned_amount': earned,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Attendance saved'),
                backgroundColor: Colors.green),
          );
        }
      }

      _loadAttendance(labourId);
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

  void _editRow(Map<String, dynamic> row) {
    setState(() {
      _editAttendanceId = row['id'] as int;
      _dateCtrl.text = row['attendance_date'] as String;
      _selectedStatus = row['status'] as String;
    });
  }

  Future<void> _deleteRow(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Attendance'),
        content: const Text('Delete this attendance record?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final db = await _db.database;
    await db.delete('labour_attendance', where: 'id = ?', whereArgs: [id]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Record deleted'), backgroundColor: Colors.green),
      );
    }
    if (_selectedLabour != null) {
      _loadAttendance(_selectedLabour!['id'] as int);
    }
  }

  Color _statusColor(String status) {
    if (status == 'Present') return Colors.green;
    if (status == 'Half Day') return Colors.orange;
    return Colors.red;
  }

  String _formatDate(String raw) {
    try {
      final parts = raw.split('-');
      final months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${parts[2]} ${months[int.parse(parts[1])]} ${parts[0]}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Entry Form
          Container(
            color: Colors.indigo.shade50,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Labour Dropdown
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: _selectedLabour,
                  decoration: const InputDecoration(
                    labelText: 'Select Labour *',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: _labourList.map((l) {
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: l,
                      child: Text(l['name'] as String),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedLabour = val;
                      _attendanceList = [];
                      _editAttendanceId = null;
                    });
                    if (val != null) _loadAttendance(val['id'] as int);
                  },
                  hint: const Text('Select labour...'),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    // Date picker
                    Expanded(
                      child: TextFormField(
                        controller: _dateCtrl,
                        readOnly: true,
                        onTap: _pickDate,
                        decoration: const InputDecoration(
                          labelText: 'Date *',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Status
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Status *',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: _statusOptions
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedStatus = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Earned preview
                if (_selectedLabour != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calculate_outlined,
                            size: 16, color: Colors.indigo),
                        const SizedBox(width: 6),
                        Text(
                          'Earned for this entry: ₹${_calcEarned(_selectedStatus, (_selectedLabour!['daily_wage_rate'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.indigo,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveAttendance,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                _editAttendanceId != null
                                    ? 'Update Attendance'
                                    : 'Save Attendance',
                              ),
                      ),
                    ),
                    if (_editAttendanceId != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _editAttendanceId = null;
                            _selectedStatus = 'Present';
                          });
                        },
                        child: const Text('Cancel Edit'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Attendance History
          if (_selectedLabour != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Attendance History — ${_selectedLabour!['name']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.indigo),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedLabour == null
                    ? const Center(
                        child: Text('Select a labour to view attendance',
                            style: TextStyle(color: Colors.grey)),
                      )
                    : _attendanceList.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_note,
                                    size: 48, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('No attendance records yet',
                                    style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () =>
                                _loadAttendance(_selectedLabour!['id'] as int),
                            child: ListView.builder(
                              itemCount: _attendanceList.length,
                              itemBuilder: (context, index) {
                                final row = _attendanceList[index];
                                final String status =
                                    row['status'] as String;
                                final double earned =
                                    (row['earned_amount'] as num).toDouble();

                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor:
                                        _statusColor(status).withValues(alpha: 0.15),
                                    child: Icon(
                                      status == 'Present'
                                          ? Icons.check
                                          : status == 'Half Day'
                                              ? Icons.looks_one
                                              : Icons.close,
                                      color: _statusColor(status),
                                      size: 16,
                                    ),
                                  ),
                                  title: Text(
                                      _formatDate(
                                          row['attendance_date'] as String),
                                      style: const TextStyle(fontSize: 13)),
                                  subtitle: Text(status,
                                      style: TextStyle(
                                          color: _statusColor(status),
                                          fontSize: 12)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '₹${earned.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit,
                                            size: 16, color: Colors.indigo),
                                        onPressed: () => _editRow(row),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 16, color: Colors.red),
                                        onPressed: () =>
                                            _deleteRow(row['id'] as int),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
