import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ss_supreme_solutions.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Customers table
    await db.execute('''
      CREATE TABLE customers (
        uuid TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        business_name TEXT,
        phone TEXT DEFAULT '',
        email TEXT,
        gstin TEXT,
        address TEXT,
        city TEXT,
        state TEXT,
        state_code TEXT,
        pincode TEXT,
        outstanding_balance REAL DEFAULT 0,
        total_billed REAL DEFAULT 0,
        total_paid REAL DEFAULT 0,
        active INTEGER DEFAULT 1
      )
    ''');

    // 2. Products catalogue table
    await db.execute('''
      CREATE TABLE products (
        uuid TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        hsn_code TEXT,
        unit TEXT DEFAULT 'PCS',
        default_rate REAL DEFAULT 0,
        gst_rate REAL DEFAULT 18.0,
        active INTEGER DEFAULT 1
      )
    ''');

    // 3. Invoices table
    await db.execute('''
      CREATE TABLE invoices (
        uuid TEXT PRIMARY KEY,
        invoice_number TEXT NOT NULL UNIQUE,
        sequence_number INTEGER NOT NULL,
        financial_year TEXT NOT NULL,
        invoice_date TEXT NOT NULL,
        due_date TEXT,
        po_number TEXT,
        po_date TEXT,
        challan_number TEXT,
        challan_date TEXT,
        customer_json TEXT NOT NULL,
        is_inter_state INTEGER DEFAULT 0,
        items_json TEXT NOT NULL,
        net_amount REAL NOT NULL,
        cgst_total REAL DEFAULT 0,
        sgst_total REAL DEFAULT 0,
        igst_total REAL DEFAULT 0,
        round_off REAL DEFAULT 0,
        grand_total REAL NOT NULL,
        amount_in_words TEXT NOT NULL,
        status TEXT DEFAULT 'finalized',
        payment_status TEXT DEFAULT 'unpaid',
        total_paid REAL DEFAULT 0,
        balance_due REAL NOT NULL,
        device_id TEXT,
        created_by TEXT,
        sync_status TEXT DEFAULT 'synced'
      )
    ''');

    // Indexes for fast bill searching
    await db.execute('CREATE INDEX idx_invoices_number ON invoices(invoice_number);');
    await db.execute('CREATE INDEX idx_invoices_date ON invoices(invoice_date);');
    await db.execute('CREATE INDEX idx_invoices_status ON invoices(status);');
    await db.execute('CREATE INDEX idx_invoices_payment ON invoices(payment_status);');

    // 4. Payments table
    await db.execute('''
      CREATE TABLE payments (
        uuid TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        invoice_number TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL,
        reference_number TEXT,
        payment_date TEXT NOT NULL,
        notes TEXT,
        received_by TEXT,
        device_id TEXT
      )
    ''');

    // 5. Sync queue table
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        retry_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 6. App settings table
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Seed common industrial hardware products
    await _seedInitialProducts(db);
  }

  Future<void> _seedInitialProducts(Database db) async {
    final initialProducts = [
      {'uuid': 'prod-1', 'description': 'Spiral Wound Gasket 2" 150# ASME CS/SS304', 'hsn_code': '8484', 'unit': 'NOS', 'default_rate': 350.0, 'gst_rate': 18.0},
      {'uuid': 'prod-2', 'description': 'Spiral Wound Gasket 3" 150# ASME CS/SS304', 'hsn_code': '8484', 'unit': 'NOS', 'default_rate': 420.0, 'gst_rate': 18.0},
      {'uuid': 'prod-3', 'description': 'Spiral Wound Gasket 4" 150# ASME CS/SS304', 'hsn_code': '8484', 'unit': 'NOS', 'default_rate': 550.0, 'gst_rate': 18.0},
      {'uuid': 'prod-4', 'description': 'Hydraulic Seal Kit (D/A 80x50 High Temp)', 'hsn_code': '8487', 'unit': 'SET', 'default_rate': 1850.0, 'gst_rate': 18.0},
      {'uuid': 'prod-5', 'description': 'Hydraulic Seal Kit (D/A 100x70)', 'hsn_code': '8487', 'unit': 'SET', 'default_rate': 2400.0, 'gst_rate': 18.0},
      {'uuid': 'prod-6', 'description': 'PTFE Virgin Teflon Gasket Sheet 3mm', 'hsn_code': '3920', 'unit': 'PCS', 'default_rate': 3400.0, 'gst_rate': 18.0},
      {'uuid': 'prod-7', 'description': 'CAF Gasket Champion 20 1.5mm', 'hsn_code': '6812', 'unit': 'MTR', 'default_rate': 850.0, 'gst_rate': 18.0},
      {'uuid': 'prod-8', 'description': 'NBR O-Ring Kit Box (Standard 386 Pcs)', 'hsn_code': '4016', 'unit': 'BOX', 'default_rate': 1250.0, 'gst_rate': 18.0},
      {'uuid': 'prod-9', 'description': 'Hydraulic High Pressure Hose Pipe 1/2" R2', 'hsn_code': '4009', 'unit': 'MTR', 'default_rate': 650.0, 'gst_rate': 18.0},
    ];

    for (final p in initialProducts) {
      await db.insert('products', {
        'uuid': p['uuid'],
        'description': p['description'],
        'hsn_code': p['hsn_code'],
        'unit': p['unit'],
        'default_rate': p['default_rate'],
        'gst_rate': p['gst_rate'],
        'active': 1
      });
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
