import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:buku_utang_warung/services/backup_crypto_service.dart';

void main() {
  final crypto = BackupCryptoService.instance;

  final sampleBackup = <String, Object?>{
    'format': 'buku_utang_warung_backup',
    'version': 1,
    'exported_at': '2026-11-14T00:00:00.000Z',
    'customers': [
      {'id': 1, 'name': 'Pelanggan Uji'},
    ],
    'transactions': [
      {'id': 1, 'customer_id': 1, 'amount': 25000},
    ],
  };

  test('Backup dapat dienkripsi dan dibuka kembali', () async {
    const password = 'WarungAman2026';

    final encrypted = await crypto.encryptBackup(
      sampleBackup,
      password,
    );

    expect(encrypted, isNotEmpty);
    expect(utf8.decode(encrypted), isNot(contains('Pelanggan Uji')));

    final restored = await crypto.decryptBackup(
      encrypted,
      password,
    );

    expect(restored['customers'], sampleBackup['customers']);
    expect(restored['transactions'], sampleBackup['transactions']);
  });

  test('Password kurang dari 8 karakter ditolak', () async {
    expect(
      () => crypto.encryptBackup(sampleBackup, '1234567'),
      throwsArgumentError,
    );
  });

  test('Password salah tidak dapat membuka backup', () async {
    final encrypted = await crypto.encryptBackup(
      sampleBackup,
      'PasswordBenar2026',
    );

    expect(
      () => crypto.decryptBackup(encrypted, 'PasswordSalah2026'),
      throwsFormatException,
    );
  });

  test('Isi ciphertext yang diubah akan ditolak', () async {
    final encrypted = await crypto.encryptBackup(
      sampleBackup,
      'PasswordBenar2026',
    );

    final envelope =
        jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;

    final ciphertext = base64Decode(envelope['ciphertext'] as String);
    ciphertext[0] ^= 1;
    envelope['ciphertext'] = base64Encode(ciphertext);

    final tampered = utf8.encode(jsonEncode(envelope));

    expect(
      () => crypto.decryptBackup(tampered, 'PasswordBenar2026'),
      throwsFormatException,
    );
  });
}
