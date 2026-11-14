import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  static const backupFormat = 'buku_utang_warung_backup';
  static const backupVersion = 1;

  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'buku_utang.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            credit_limit INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            amount INTEGER NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            date INTEGER NOT NULL,
            due_date INTEGER,
            FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_txn_customer ON transactions(customer_id)',
        );
      },
    );
  }

  Future<List<Customer>> customers() async {
    final db = await _database;
    final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> customer(int id) async {
    final db = await _database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<int> insertCustomer(Customer c) async {
    final db = await _database;
    return db.insert('customers', c.toMap());
  }

  Future<void> updateCustomer(Customer c) async {
    final db = await _database;
    await db.update('customers', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<void> deleteCustomer(int id) async {
    final db = await _database;
    await db.delete('transactions', where: 'customer_id = ?', whereArgs: [id]);
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Txn>> allTxns() async {
    final db = await _database;
    final rows = await db.query('transactions');
    return rows.map(Txn.fromMap).toList();
  }

  Future<List<Txn>> txnsFor(int customerId) async {
    final db = await _database;
    final rows = await db.query(
      'transactions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<int> insertTxn(Txn t) async {
    final db = await _database;
    return db.insert('transactions', t.toMap());
  }

  Future<void> deleteTxn(int id) async {
    final db = await _database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // Membuat snapshot JSON tanpa mengubah database aktif.
  Future<Map<String, Object?>> exportBackup() async {
    final db = await _database;
    return {
      'format': backupFormat,
      'version': backupVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'customers': await db.query('customers', orderBy: 'id ASC'),
      'transactions': await db.query('transactions', orderBy: 'id ASC'),
    };
  }

  static List<Map<String, Object?>> _rows(
    Object? value,
    String label,
  ) {
    if (value is! List) {
      throw FormatException('Bagian $label bukan daftar yang valid');
    }

    return value.map((item) {
      if (item is! Map) {
        throw FormatException('Ada data $label yang tidak valid');
      }
      return Map<String, Object?>.from(item);
    }).toList();
  }

  // Validasi lengkap dilakukan sebelum database boleh diubah.
  static void validateBackupData(Map<String, dynamic> data) {
    if (data['format'] != backupFormat) {
      throw const FormatException('Format file bukan backup Buku Utang Warung');
    }
    if (data['version'] != backupVersion) {
      throw const FormatException('Versi backup tidak didukung');
    }

    final customers = _rows(data['customers'], 'pelanggan');
    final transactions = _rows(data['transactions'], 'transaksi');

    final customerIds = <int>{};

    for (final row in customers) {
      final id = row['id'];
      if (id is! int || id <= 0 || !customerIds.add(id)) {
        throw const FormatException('ID pelanggan tidak valid atau duplikat');
      }
      if (row['name'] is! String ||
          row['phone'] is! String ||
          row['note'] is! String ||
          row['credit_limit'] is! int ||
          (row['credit_limit'] as int) < 0 ||
          row['created_at'] is! int) {
        throw const FormatException('Data pelanggan tidak lengkap atau rusak');
      }
    }

    final txnIds = <int>{};

    for (final row in transactions) {
      final id = row['id'];
      final customerId = row['customer_id'];
      final type = row['type'];
      final amount = row['amount'];
      final dueDate = row['due_date'];

      if (id is! int || id <= 0 || !txnIds.add(id)) {
        throw const FormatException('ID transaksi tidak valid atau duplikat');
      }
      if (customerId is! int || !customerIds.contains(customerId)) {
        throw const FormatException(
          'Transaksi mengacu ke pelanggan yang tidak ditemukan',
        );
      }
      if (type != 'utang' && type != 'bayar') {
        throw const FormatException('Jenis transaksi tidak dikenal');
      }
      if (amount is! int || amount <= 0 ||
          row['note'] is! String ||
          row['date'] is! int ||
          (dueDate != null && dueDate is! int)) {
        throw const FormatException('Data transaksi tidak lengkap atau rusak');
      }
    }
  }

  // Penggantian seluruh data dilakukan dalam satu transaksi SQLite.
  // Jika satu insert gagal, SQLite membatalkan seluruh proses.
  Future<void> restoreBackup(Map<String, dynamic> data) async {
    validateBackupData(data);

    final customers = _rows(data['customers'], 'pelanggan');
    final transactions = _rows(data['transactions'], 'transaksi');
    final db = await _database;

    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('customers');

      for (final row in customers) {
        await txn.insert('customers', row);
      }

      for (final row in transactions) {
        await txn.insert('transactions', row);
      }
    });
  }
}
