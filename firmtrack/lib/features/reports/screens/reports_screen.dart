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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
          ],
        ),
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
