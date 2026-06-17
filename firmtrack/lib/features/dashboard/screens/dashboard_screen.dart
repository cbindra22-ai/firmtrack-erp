import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;

  double _todaySales = 0;
  double _monthlySales = 0;
  double _customerOutstanding = 0;
  double _customerAdvance = 0;
  double _monthlyExpenses = 0;

  List<Map<String, dynamic>> _lowStockProducts = [];

  final _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // Called every time screen is revisited
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final monthStart =
          DateFormat('yyyy-MM-dd').format(DateTime(DateTime.now().year, DateTime.now().month, 1));
      final monthEnd = DateFormat('yyyy-MM-dd').format(
          DateTime(DateTime.now().year, DateTime.now().month + 1, 0));

      // Today's Sales
      final todayResult = await db.rawQuery(
        '''SELECT COALESCE(SUM(ii.amount), 0) as total
           FROM invoice_items ii
           JOIN invoices i ON ii.invoice_id = i.id
           WHERE i.invoice_date = ? AND i.status != 'Cancelled'
        ''',
        [today],
      );
      _todaySales = (todayResult.first['total'] as num?)?.toDouble() ?? 0;

      // Monthly Sales
      final monthlyResult = await db.rawQuery(
        '''SELECT COALESCE(SUM(ii.amount), 0) as total
           FROM invoice_items ii
           JOIN invoices i ON ii.invoice_id = i.id
           WHERE i.invoice_date >= ? AND i.invoice_date <= ?
             AND i.status != 'Cancelled'
        ''',
        [monthStart, monthEnd],
      );
      _monthlySales = (monthlyResult.first['total'] as num?)?.toDouble() ?? 0;

      // Customer Outstanding
      final outstandingResult = await db.rawQuery(
        '''SELECT COALESCE(SUM(balance), 0) as total
           FROM invoices
           WHERE status IN ('Unpaid', 'Partially Paid')
        ''',
      );
      _customerOutstanding =
          (outstandingResult.first['total'] as num?)?.toDouble() ?? 0;

      // Customer Advance
      final advanceResult = await db.rawQuery(
        '''SELECT COALESCE(SUM(total_paid - total_invoiced), 0) as total
           FROM (
             SELECT c.id,
               COALESCE((SELECT SUM(amount) FROM payments WHERE customer_id = c.id), 0) as total_paid,
               COALESCE((SELECT SUM(total_amount) FROM invoices WHERE customer_id = c.id AND status != 'Cancelled'), 0) as total_invoiced
             FROM customers c
           ) t
           WHERE total_paid > total_invoiced
        ''',
      );
      _customerAdvance =
          (advanceResult.first['total'] as num?)?.toDouble() ?? 0;

      // Monthly Expenses
      final expenseResult = await db.rawQuery(
        '''SELECT COALESCE(SUM(amount), 0) as total
           FROM expenses
           WHERE expense_date >= ? AND expense_date <= ?
        ''',
        [monthStart, monthEnd],
      );
      _monthlyExpenses =
          (expenseResult.first['total'] as num?)?.toDouble() ?? 0;

      // Low Stock Products
      final lowStockResult = await db.rawQuery(
        '''SELECT p.id, p.name, p.unit, p.min_stock_level,
             COALESCE((
               SELECT SUM(CASE WHEN movement_type IN ('Opening Stock','Purchase','Production')
                          THEN quantity ELSE -quantity END)
               FROM stock_in WHERE product_id = p.id
             ), 0) as current_stock
           FROM products p
           WHERE p.min_stock_level IS NOT NULL AND p.min_stock_level > 0
           HAVING current_stock < p.min_stock_level
           ORDER BY current_stock ASC
        ''',
      );
      _lowStockProducts = lowStockResult;
    } catch (e) {
      debugPrint('Dashboard load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FirmTrack'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.pushNamed(context, '/company_settings')
                  .then((_) => _loadDashboardData());
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryCards(),
                    const SizedBox(height: 24),
                    _buildQuickActions(),
                    const SizedBox(height: 24),
                    _buildLowStockSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Summary',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: "Today's Sales",
                value: _currencyFormat.format(_todaySales),
                icon: Icons.today,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: 'Monthly Sales',
                value: _currencyFormat.format(_monthlySales),
                icon: Icons.bar_chart,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Outstanding',
                value: _currencyFormat.format(_customerOutstanding),
                icon: Icons.account_balance_wallet_outlined,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: 'Advance',
                value: _currencyFormat.format(_customerAdvance),
                icon: Icons.savings_outlined,
                color: Colors.teal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SummaryCard(
          label: 'Monthly Expenses',
          value: _currencyFormat.format(_monthlyExpenses),
          icon: Icons.receipt_long_outlined,
          color: Colors.red,
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickActionButton(
                icon: Icons.add_circle_outline,
                label: 'New Invoice',
                onTap: () => Navigator.pushNamed(context, '/invoice-form').then((_) => _loadDashboardData()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionButton(
                icon: Icons.inventory_2_outlined,
                label: 'Add Stock',
                onTap: () => Navigator.pushNamed(context, '/stock-in').then((_) => _loadDashboardData()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _QuickActionButton(
                icon: Icons.payments_outlined,
                label: 'Add Payment',
                onTap: () => Navigator.pushNamed(context, '/payment-form').then((_) => _loadDashboardData()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionButton(
                icon: Icons.money_off_outlined,
                label: 'Add Expense',
                onTap: () => Navigator.pushNamed(context, '/expense-form').then((_) => _loadDashboardData()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLowStockSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
            const SizedBox(width: 6),
            const Text(
              'Low Stock Alerts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '${_lowStockProducts.length} items',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_lowStockProducts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Column(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green, size: 36),
                SizedBox(height: 8),
                Text('All stock levels are OK',
                    style: TextStyle(color: Colors.green)),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _lowStockProducts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _lowStockProducts[index];
              final currentStock =
                  (item['current_stock'] as num?)?.toDouble() ?? 0;
              final minLevel =
                  (item['min_stock_level'] as num?)?.toDouble() ?? 0;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.inventory_2,
                    color: Colors.orange, size: 22),
                title: Text(
                  item['name'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Min: ${minLevel.toStringAsFixed(2)} ${item['unit']}',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                trailing: Text(
                  '${currentStock.toStringAsFixed(2)} ${item['unit']}',
                  style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                onTap: () => Navigator.pushNamed(context, '/stock-list'),
              );
            },
          ),
      ],
    );
  }
}

// ─── Summary Card Widget ──────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool fullWidth;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Action Button Widget ───────────────────────────────────────────────

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: Theme.of(context).colorScheme.primary, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}