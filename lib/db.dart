import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Penyimpanan lokal (SQLite). Semua data ada di HP, jalan tanpa internet.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

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
            'CREATE INDEX idx_txn_customer ON transactions(customer_id)');
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
}
