import 'package:flutter/material.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Select Report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          _buildReportTile(
            context,
            icon: Icons.receipt_long,
            title: 'Sales Report',
            subtitle: 'Total sales & payments received',
            color: Colors.blue,
            route: '/sales-report',
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            context,
            icon: Icons.money_off,
            title: 'Expense Report',
            subtitle: 'Total expenses by category',
            color: Colors.orange,
            route: '/expense-report',
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            context,
            icon: Icons.bar_chart,
            title: 'Profit & Loss',
            subtitle: 'Income vs expenses, net profit or loss',
            color: Colors.green,
            route: '/profit-loss',
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            context,
            icon: Icons.inventory_2,
            title: 'Stock Report',
            subtitle: 'Product wise stock movement & current stock',
            color: Colors.teal,
            route: '/stock-report',
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            context,
            icon: Icons.account_balance_wallet,
            title: 'Customer Outstanding',
            subtitle: 'Pending amount per customer',
            color: Colors.red,
            route: '/customer-outstanding-report',
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            context,
            icon: Icons.savings,
            title: 'Customer Advance',
            subtitle: 'Advance balance per customer',
            color: Colors.purple,
            route: '/customer-advance-report',
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            context,
            icon: Icons.people,
            title: 'Daily Wage Labour Report',
            subtitle: 'Attendance, earned, paid & balance',
            color: Colors.brown,
            route: '/daily-wage-report',
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            context,
            icon: Icons.precision_manufacturing,
            title: 'Piece Rate Labour Report',
            subtitle: 'Production, earned, paid & balance',
            color: Colors.indigo,
            route: '/piece-rate-report',
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            context,
            icon: Icons.payment,
            title: 'Payment Collection Report',
            subtitle: 'All payments received by date & customer',
            color: Colors.cyan,
            route: '/payment-collection-report',
          ),
        ],
      ),
    );
  }

  Widget _buildReportTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String route,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, route),
      ),
    );
  }
}
