import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';

class LabourListScreen extends StatefulWidget {
  const LabourListScreen({super.key});

  @override
  State<LabourListScreen> createState() => _LabourListScreenState();
}

class _LabourListScreenState extends State<LabourListScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _labourList = [];
  List<Map<String, dynamic>> _filtered = [];
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLabour();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLabour() async {
    setState(() => _isLoading = true);
    final db = await _db.database;
    final List<Map<String, dynamic>> labourRows =
        await db.query('labour', orderBy: 'name ASC');

    final List<Map<String, dynamic>> result = [];
    for (final labour in labourRows) {
      final int labourId = labour['id'] as int;
      final String labourType = labour['labour_type'] as String;

      double totalEarned = 0.0;
      double totalPaid = 0.0;

      if (labourType == 'Daily Wage') {
        final earnedRows = await db.rawQuery(
          'SELECT COALESCE(SUM(earned_amount), 0) as total FROM labour_attendance WHERE labour_id = ?',
          [labourId],
        );
        totalEarned = (earnedRows.first['total'] as num?)?.toDouble() ?? 0.0;
      } else {
        // Piece Rate — earned from production entries
        final earnedRows = await db.rawQuery(
          'SELECT COALESCE(SUM(lpi.quantity_made * lpi.rate_per_unit), 0) as total '
          'FROM labour_production lp '
          'JOIN labour_production_items lpi ON lpi.production_id = lp.id '
          "WHERE lp.labour_id = ? AND lp.status != 'Cancelled'",
          [labourId],
        );
        totalEarned = (earnedRows.first['total'] as num?)?.toDouble() ?? 0.0;
      }

      final paidRows = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total FROM labour_payments WHERE labour_id = ?',
        [labourId],
      );
      totalPaid = (paidRows.first['total'] as num?)?.toDouble() ?? 0.0;

      final double balance = totalEarned - totalPaid;

      result.add({
        ...labour,
        'total_earned': totalEarned,
        'total_paid': totalPaid,
        'balance': balance < 0 ? 0.0 : balance,
      });
    }

    setState(() {
      _labourList = result;
      _filtered = result;
      _isLoading = false;
    });
  }

  void _onSearch(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = _labourList
          .where((l) => (l['name'] as String).toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _deleteLabour(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Labour'),
        content: Text('Delete "$name"? This cannot be undone.'),
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
    await db.delete('labour', where: 'id = ?', whereArgs: [id]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Labour deleted'), backgroundColor: Colors.green),
      );
    }
    _loadLabour();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Labour'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search labour...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('No labour found',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadLabour,
                        child: ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final labour = _filtered[index];
                            final double balance =
                                (labour['balance'] as num).toDouble();
                            final String labourType =
                                labour['labour_type'] as String;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: labourType == 'Daily Wage'
                                      ? Colors.blue.shade100
                                      : Colors.orange.shade100,
                                  child: Icon(
                                    labourType == 'Daily Wage'
                                        ? Icons.calendar_today
                                        : Icons.precision_manufacturing,
                                    color: labourType == 'Daily Wage'
                                        ? Colors.blue
                                        : Colors.orange,
                                    size: 20,
                                  ),
                                ),
                                title: Text(labour['name'] as String,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(labourType,
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12)),
                                    if (labour['phone'] != null &&
                                        (labour['phone'] as String).isNotEmpty)
                                      Text(labour['phone'] as String,
                                          style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12)),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Due: ₹${balance.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: balance > 0
                                            ? Colors.red.shade700
                                            : Colors.green.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  await Navigator.pushNamed(
                                    context,
                                    '/labour-form',
                                    arguments: labour,
                                  );
                                  _loadLabour();
                                },
                                onLongPress: () => _deleteLabour(
                                    labour['id'] as int,
                                    labour['name'] as String),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(context, '/labour-form');
          _loadLabour();
        },
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: _filtered.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _bottomStat('Total Labour', '${_filtered.length}',
                      Colors.indigo),
                  _bottomStat(
                    'Total Due',
                    '₹${_filtered.fold(0.0, (s, l) => s + (l['balance'] as num).toDouble()).toStringAsFixed(2)}',
                    Colors.red.shade700,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _bottomStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 15)),
        Text(label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
      ],
    );
  }
}
