import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../constants/app_constants.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);
    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('PRAGMA foreign_keys = ON;');

    // 1. company
    await db.execute('''
      CREATE TABLE IF NOT EXISTS company (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        company_name            TEXT    NOT NULL,
        logo                    TEXT,
        address                 TEXT,
        phone                   TEXT,
        invoice_prefix          TEXT    NOT NULL DEFAULT 'INV',
        invoice_starting_number INTEGER NOT NULL DEFAULT 1,
        created_at              TEXT    NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // 2. products
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        product_name    TEXT    NOT NULL,
        product_code    TEXT,
        category        TEXT,
        unit            TEXT    NOT NULL,
        description     TEXT,
        min_stock_level REAL    NOT NULL DEFAULT 0,
        created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // 3. customers
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        name            TEXT    NOT NULL,
        phone           TEXT,
        address         TEXT,
        opening_balance REAL    NOT NULL DEFAULT 0,
        created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // 4. invoices
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number  TEXT    NOT NULL UNIQUE,
        customer_id     INTEGER NOT NULL,
        invoice_date    TEXT    NOT NULL,
        total_amount    REAL    NOT NULL DEFAULT 0,
        paid_amount     REAL    NOT NULL DEFAULT 0,
        balance         REAL    NOT NULL DEFAULT 0,
        status          TEXT    NOT NULL DEFAULT 'Unpaid',
        advance_used    REAL    NOT NULL DEFAULT 0,
        notes           TEXT,
        created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
        cancelled_at    TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    // 5. invoice_items
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id  INTEGER NOT NULL,
        product_id  INTEGER NOT NULL,
        quantity    REAL    NOT NULL,
        unit        TEXT    NOT NULL,
        rate        REAL    NOT NULL,
        amount      REAL    NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id),
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // 6. payments
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payments (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id      INTEGER NOT NULL,
        amount           REAL    NOT NULL,
        payment_date     TEXT    NOT NULL,
        payment_mode     TEXT    NOT NULL,
        reference_number TEXT,
        notes            TEXT,
        created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    // 7. expenses
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id                 INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_date       TEXT    NOT NULL,
        category           TEXT    NOT NULL,
        amount             REAL    NOT NULL,
        note               TEXT,
        is_auto            INTEGER NOT NULL DEFAULT 0,
        labour_payment_id  INTEGER,
        created_at         TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (labour_payment_id) REFERENCES labour_payments(id)
      )
    ''');

    // 8. stock_in
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_in (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id      INTEGER NOT NULL,
        movement_type   TEXT    NOT NULL,
        quantity        REAL    NOT NULL,
        unit            TEXT    NOT NULL,
        reference       TEXT,
        labour_id       INTEGER,
        production_id   INTEGER,
        movement_date   TEXT    NOT NULL,
        created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (product_id)    REFERENCES products(id),
        FOREIGN KEY (labour_id)     REFERENCES labour(id),
        FOREIGN KEY (production_id) REFERENCES labour_production(id)
      )
    ''');

    // 9. labour
    await db.execute('''
      CREATE TABLE IF NOT EXISTS labour (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        name             TEXT    NOT NULL,
        phone            TEXT,
        address          TEXT,
        labour_type      TEXT    NOT NULL,
        daily_wage_rate  REAL,
        join_date        TEXT,
        created_at       TEXT    NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // 10. labour_attendance
    await db.execute('''
      CREATE TABLE IF NOT EXISTS labour_attendance (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        labour_id       INTEGER NOT NULL,
        attendance_date TEXT    NOT NULL,
        status          TEXT    NOT NULL,
        earned_amount   REAL    NOT NULL DEFAULT 0,
        created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (labour_id) REFERENCES labour(id)
      )
    ''');

    // 11. labour_payments
    await db.execute('''
      CREATE TABLE IF NOT EXISTS labour_payments (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        labour_id        INTEGER NOT NULL,
        amount           REAL    NOT NULL,
        payment_date     TEXT    NOT NULL,
        payment_mode     TEXT,
        reference_number TEXT,
        notes            TEXT,
        created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (labour_id) REFERENCES labour(id)
      )
    ''');

    // 12. labour_piece_rates
    await db.execute('''
      CREATE TABLE IF NOT EXISTS labour_piece_rates (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        labour_id     INTEGER NOT NULL,
        product_id    INTEGER NOT NULL,
        rate_per_unit REAL    NOT NULL,
        unit          TEXT    NOT NULL,
        created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (labour_id)  REFERENCES labour(id),
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // 13. labour_production
    await db.execute('''
      CREATE TABLE IF NOT EXISTS labour_production (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        labour_id       INTEGER NOT NULL,
        production_date TEXT    NOT NULL,
        total_earned    REAL    NOT NULL DEFAULT 0,
        status          TEXT    NOT NULL DEFAULT 'Active',
        cancelled_at    TEXT,
        created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (labour_id) REFERENCES labour(id)
      )
    ''');

    // 14. labour_production_items
    await db.execute('''
      CREATE TABLE IF NOT EXISTS labour_production_items (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        production_id       INTEGER NOT NULL,
        product_id          INTEGER NOT NULL,
        quantity_made       REAL    NOT NULL,
        unit_made           TEXT    NOT NULL,
        rate                REAL    NOT NULL,
        amount              REAL    NOT NULL,
        material_product_id INTEGER,
        consumed_qty        REAL,
        consumed_unit       TEXT,
        created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (production_id)       REFERENCES labour_production(id),
        FOREIGN KEY (product_id)          REFERENCES products(id),
        FOREIGN KEY (material_product_id) REFERENCES products(id)
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_customer_id ON invoices(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_invoice_date ON invoices(invoice_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice_id ON invoice_items(invoice_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoice_items_product_id ON invoice_items(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_customer_id ON payments(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_payment_date ON payments(payment_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_in_product_id ON stock_in(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_in_movement_type ON stock_in(movement_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_in_movement_date ON stock_in(movement_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_in_production_id ON stock_in(production_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_labour_attendance_labour_id ON labour_attendance(labour_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_labour_attendance_date ON labour_attendance(attendance_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_labour_payments_labour_id ON labour_payments(labour_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_labour_piece_rates_labour_id ON labour_piece_rates(labour_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_labour_piece_rates_product_id ON labour_piece_rates(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_labour_production_labour_id ON labour_production(labour_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_labour_production_date ON labour_production(production_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_labour_production_status ON labour_production(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_labour_production_items_production_id ON labour_production_items(production_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_labour_production_items_product_id ON labour_production_items(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_expense_date ON expenses(expense_date)');
  }
}
