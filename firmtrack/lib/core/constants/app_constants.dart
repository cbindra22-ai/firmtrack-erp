class AppConstants {
  static const String appName = 'FirmTrack';
  static const String dbName = 'firmtrack.db';
  static const int dbVersion = 1;

  // Units
  static const List<String> units = [
    'Kg', 'Gram', 'Number', 'Piece', 'Bundle', 'Box', 'Litre', 'Metre', 'Other'
  ];

  // Invoice Status
  static const List<String> invoiceStatus = [
    'Unpaid', 'Partially Paid', 'Paid', 'Cancelled'
  ];

  // Payment Modes
  static const List<String> paymentModes = [
    'Cash', 'UPI', 'Cheque', 'Bank Transfer'
  ];

  // Expense Categories
  static const List<String> expenseCategories = [
    'Material Purchase', 'Labour Salary', 'Transport',
    'Tea & Daily Expenses', 'Electricity', 'Rent', 'Other'
  ];

  // Stock Movement Types
  static const List<String> movementTypes = [
    'Opening Stock', 'Purchase', 'Manual Addition',
    'Production', 'Production Reversed', 'Consumed Reversed'
  ];

  // Labour Types
  static const List<String> labourTypes = ['Daily Wage', 'Piece Rate'];

  // Attendance Status
  static const List<String> attendanceStatus = ['Present', 'Half Day', 'Absent'];
}
