import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/database/database_helper.dart';
import 'features/company_settings/screens/company_settings_screen.dart';
import 'features/inventory/screens/stock_list_screen.dart';
import 'features/inventory/screens/stock_in_screen.dart';
import 'features/customers/screens/customer_list_screen.dart';
import 'features/customers/screens/customer_form_screen.dart';
import 'features/labour/screens/labour_list_screen.dart';
import 'features/labour/screens/labour_form_screen.dart';
import 'features/labour/screens/labour_attendance_screen.dart';
import 'features/labour/screens/labour_payment_screen.dart';
import 'features/labour/screens/labour_detail_screen.dart';
import 'features/labour/screens/piece_rate_screens.dart';
import 'features/production/screens/production_list_screen.dart';
import 'features/production/screens/production_form_screen.dart';
import 'features/invoices/screens/invoice_list_screen.dart';
import 'features/invoices/screens/invoice_form_screen.dart';
import 'features/invoices/screens/invoice_detail_screen.dart';
import 'features/payments/screens/payment_form_screen.dart';
import 'features/payments/screens/customer_ledger_screen.dart';
import 'features/expenses/screens/expense_list_screen.dart';
import 'features/expenses/screens/expense_form_screen.dart';
import 'features/backup/screens/backup_screen.dart';
import 'features/backup/screens/restore_screen.dart';
import 'features/reports/screens/reports_screen.dart';
import 'features/reports/screens/sales_report_screen.dart';
import 'features/reports/screens/expense_report_screen.dart';
import 'features/reports/screens/profit_loss_screen.dart';
import 'features/reports/screens/stock_report_screen.dart';
import 'features/reports/screens/customer_outstanding_report_screen.dart';
import 'features/reports/screens/customer_advance_report_screen.dart';
import 'features/reports/screens/daily_wage_report_screen.dart';
import 'features/reports/screens/piece_rate_report_screen.dart';
import 'features/reports/screens/payment_collection_report_screen.dart';
import 'shared/widgets/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize database
  await DatabaseHelper.instance.database;

  // Check if company is set up
  final isSetup = await DatabaseHelper.instance.isCompanySetup();

  runApp(FirmTrackApp(isCompanySetup: isSetup));
}

class FirmTrackApp extends StatelessWidget {
  final bool isCompanySetup;

  const FirmTrackApp({super.key, required this.isCompanySetup});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FirmTrack ERP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      ),
      initialRoute: isCompanySetup ? '/dashboard' : '/company_settings',
      routes: {
        '/company_settings': (context) => const CompanySettingsScreen(),
        '/dashboard': (context) => const MainShell(),
        '/stock-list': (context) => const StockListScreen(),
        '/stock-in': (context) => const StockInScreen(),
        '/customer-list': (context) => const CustomerListScreen(),
        '/customer-form': (context) => const CustomerFormScreen(),
        '/labour-list': (context) => const LabourListScreen(),
        '/labour-form': (context) => const LabourFormScreen(),
        '/labour-attendance': (context) => const LabourAttendanceScreen(),
        '/labour-payment': (context) => const LabourPaymentScreen(),
        '/labour-detail': (context) => const LabourDetailScreen(),
        '/piece-rate-card': (context) => const PieceRateCardScreen(),
        '/piece-rate-form': (context) => const PieceRateFormScreen(),
        '/production-list': (context) => const ProductionListScreen(),
        '/production-form': (context) => const ProductionFormScreen(),
        '/invoice-list': (context) => const InvoiceListScreen(),
        '/invoice-form': (context) => const InvoiceFormScreen(),
        '/invoice-detail': (context) => const InvoiceDetailScreen(),
        '/payment-form': (context) => const PaymentFormScreen(),
        '/customer-ledger': (context) => const CustomerLedgerScreen(),
        '/expense-list': (context) => const ExpenseListScreen(),
        '/expense-form': (context) => const ExpenseFormScreen(),
        '/backup': (context) => const BackupScreen(),
        '/restore': (context) => const RestoreScreen(),
      '/reports': (context) => const ReportsScreen(),
      '/sales-report': (context) => const SalesReportScreen(),
      '/expense-report': (context) => const ExpenseReportScreen(),
      '/profit-loss': (context) => const ProfitLossScreen(),
      '/stock-report': (context) => const StockReportScreen(),
      '/customer-outstanding-report': (context) => const CustomerOutstandingReportScreen(),
      '/customer-advance-report': (context) => const CustomerAdvanceReportScreen(),
      '/daily-wage-report': (context) => const DailyWageReportScreen(),
      '/piece-rate-report': (context) => const PieceRateReportScreen(),
      '/payment-collection-report': (context) => const PaymentCollectionReportScreen(),
      },
    );
  }
}