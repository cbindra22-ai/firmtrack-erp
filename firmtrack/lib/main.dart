import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/database/database_helper.dart';
import 'features/company_settings/screens/company_settings_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/inventory/screens/stock_list_screen.dart';
import 'features/inventory/screens/stock_in_screen.dart';
import 'features/customers/screens/customer_list_screen.dart';
import 'features/customers/screens/customer_form_screen.dart';
import 'features/labour/screens/labour_list_screen.dart';
import 'features/labour/screens/labour_form_screen.dart';
import 'features/labour/screens/labour_attendance_screen.dart';
import 'features/labour/screens/labour_payment_screen.dart';
import 'features/production/screens/production_list_screen.dart';
import 'features/production/screens/production_form_screen.dart';

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
        '/dashboard': (context) => const DashboardScreen(),
        '/stock-list': (context) => const StockListScreen(),
        '/stock-in': (context) => const StockInScreen(),
        '/customer-list': (context) => const CustomerListScreen(),
        '/customer-form': (context) => const CustomerFormScreen(),
        '/labour-list': (context) => const LabourListScreen(),
        '/labour-form': (context) => const LabourFormScreen(),
        '/labour-attendance': (context) => const LabourAttendanceScreen(),
        '/labour-payment': (context) => const LabourPaymentScreen(),
        '/production-list': (context) => const ProductionListScreen(),
        '/production-form': (context) => const ProductionFormScreen(),
      },
    );
  }
}