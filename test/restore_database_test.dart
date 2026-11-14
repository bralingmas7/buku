import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/db.dart';

void main() {
  late Database rawDb;
  late AppDb appDb;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    rawDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => AppDb.createSchema(db),
      ),
    );
    appDb = AppDb.forTesting(rawDb);
  });

  tearDown(() async {
    await rawDb.close();
  });

  Future<void> seedOldData() async {
    await rawDb.insert('customers', {
      'id': 1,
      'name': 'Data Lama',
      'phone': '',
      'note': '',
      'credit_limit': 0,
      'created_at': 1700000000000,
    });
    await rawDb.insert('transactions', {
      'id': 1,
      'customer_id': 1,
      'type': 'utang',
      'amount': 100,
      'note': 'Transaksi lama',
      'date': 1700000000000,
      'due_date': null,
    });
  }

  Map<String, dynamic> validBackup({int amount = 500}) => {
        'format': AppDb.backupFormat,
        'version': AppDb.backupVersion,
        'exported_at': '2026-11-14T00:00:00Z',
        'customers': [
          {
            'id': 2,
            'name': 'Data Backup',
            'phone': '08123456789',
            'note': 'Hasil restore',
            'credit_limit': 1000,
            'created_at': 1700000001000,
          },
        ],
        'transactions': [
          {
            'id': 2,
            'customer_id': 2,
            'type': 'utang',
            'amount': amount,
            'note': 'Transaksi backup',
            'date': 1700000001000,
            'due_date': null,
          },
        ],
      };

  test('restore berhasil mengganti seluruh data lama', () async {
    await seedOldData();

    await appDb.restoreBackup(validBackup());

    expect(await appDb.customer(1), isNull);
    expect((await appDb.customer(2))?.name, 'Data Backup');

    final txns = await appDb.allTxns();
    expect(txns, hasLength(1));
    expect(txns.single.amount, 500);
    expect(txns.single.customerId, 2);
  });

  test('backup tidak valid ditolak tanpa mengubah data lama', () async {
    await seedOldData();
    final invalid = validBackup()..['version'] = 999;

    await expectLater(
      appDb.restoreBackup(invalid),
      throwsA(isA<FormatException>()),
    );

    expect((await appDb.customer(1))?.name, 'Data Lama');
    expect(await appDb.customer(2), isNull);
    expect((await appDb.allTxns()).single.amount, 100);
  });

  test('kegagalan insert membatalkan seluruh restore', () async {
    await seedOldData();

    await rawDb.execute('''
      CREATE TRIGGER reject_restore_transaction
      BEFORE INSERT ON transactions
      WHEN NEW.amount = 9999
      BEGIN
        SELECT RAISE(ABORT, 'simulasi kegagalan insert');
      END
    ''');

    await expectLater(
      appDb.restoreBackup(validBackup(amount: 9999)),
      throwsA(isA<Exception>()),
    );

    expect((await appDb.customer(1))?.name, 'Data Lama');
    expect(await appDb.customer(2), isNull);
    expect((await appDb.allTxns()).single.amount, 100);
  });
}
