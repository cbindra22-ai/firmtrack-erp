import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants/app_constants.dart';
import 'core/database/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize database on startup
  await DatabaseHelper.instance.database;

  // Check if company is already set up
  final bool isCompanySetup = await _checkCompanySetup();

  runApp(FirmTrackApp(isCompanySetup: isCompanySetup));
}

/// Check if company settings have been saved
Future<bool> _checkCompanySetup() async {
  try {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      'company',
      columns: ['id'],
      limit: 1,
    );
    return result.isNotEmpty;
  } catch (e) {
    debugPrint('Error checking company setup: $e');
    return false;
  }
}

class FirmTrackApp extends StatelessWidget {
  final bool isCompanySetup;

  const FirmTrackApp({super.key, required this.isCompanySetup});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: _buildAppTheme(),
      home: isCompanySetup
          ? const _PlaceholderDashboard()   // Will replace with DashboardScreen
          : const _PlaceholderCompanySetup(), // Will replace with CompanySettingsScreen
    );
  }

  ThemeData _buildAppTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1565C0), // Deep Blue — primary brand color
        brightness: Brightness.light,
      ),
      useMaterial3: true,

      // AppBar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 2,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Card theme
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // ElevatedButton theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // InputDecoration theme
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),

      // SnackBar theme
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),

      // Bottom navigation theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: Color(0xFF1565C0),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }
}

// ─── Placeholder Screens (Replace in next steps) ──────────────────────────────

/// Placeholder — will be replaced by CompanySettingsScreen in Step 2
class _PlaceholderCompanySetup extends StatelessWidget {
  const _PlaceholderCompanySetup();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Company Setup')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.business, size: 64, color: Color(0xFF1565C0)),
            SizedBox(height: 16),
            Text(
              'Company Settings Screen',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('(Coming in Step 2)', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// Placeholder — will be replaced by DashboardScreen in Step 3
class _PlaceholderDashboard extends StatelessWidget {
  const _PlaceholderDashboard();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dashboard, size: 64, color: Color(0xFF1565C0)),
            SizedBox(height: 16),
            Text(
              'Dashboard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('(Coming in Step 3)', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}