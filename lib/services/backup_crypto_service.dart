import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class BackupCryptoService {
  BackupCryptoService._();

  static final BackupCryptoService instance = BackupCryptoService._();

  static const int minimumPasswordLength = 8;
  static const int _version = 1;
  static const int _iterations = 310000;
  static const int _maximumEncryptedBytes = 100 * 1024 * 1024;

  static const String _format = 'buku_utang_warung_encrypted_backup';
  static const String _cipherName = 'AES-256-GCM';
  static const String _kdfName = 'PBKDF2-HMAC-SHA256';

  final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  final AesGcm _cipher = AesGcm.with256bits();

  void _validatePassword(String password) {
    if (password.runes.length < minimumPasswordLength) {
      throw ArgumentError(
        'Password backup minimal $minimumPasswordLength karakter.',
      );
    }
  }

  Future<Uint8List> encryptBackup(
    Map<String, Object?> backup,
    String password,
  ) async {
    _validatePassword(password);

    final salt = Uint8List(16);
    final random = Random.secure();

    for (var i = 0; i < salt.length; i++) {
      salt[i] = random.nextInt(256);
    }

    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );

    final clearBytes = utf8.encode(jsonEncode(backup));
    final encrypted = await _cipher.encrypt(
      clearBytes,
      secretKey: key,
    );

    final envelope = <String, Object?>{
      'format': _format,
      'version': _version,
      'cipher': _cipherName,
      'kdf': _kdfName,
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(encrypted.nonce),
      'ciphertext': base64Encode(encrypted.cipherText),
      'mac': base64Encode(encrypted.mac.bytes),
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  Future<Map<String, dynamic>> decryptBackup(
    List<int> encryptedBytes,
    String password,
  ) async {
    _validatePassword(password);

    if (encryptedBytes.isEmpty ||
        encryptedBytes.length > _maximumEncryptedBytes) {
      throw const FormatException('Ukuran file backup tidak valid.');
    }

    final decodedEnvelope = jsonDecode(utf8.decode(encryptedBytes));

    if (decodedEnvelope is! Map<String, dynamic>) {
      throw const FormatException('Format file backup tidak valid.');
    }

    final envelope = decodedEnvelope;

    if (envelope['format'] != _format ||
        envelope['version'] != _version ||
        envelope['cipher'] != _cipherName ||
        envelope['kdf'] != _kdfName ||
        envelope['iterations'] != _iterations) {
      throw const FormatException(
        'Format atau versi enkripsi backup tidak didukung.',
      );
    }

    try {
      final salt = base64Decode(envelope['salt'] as String);
      final nonce = base64Decode(envelope['nonce'] as String);
      final ciphertext = base64Decode(envelope['ciphertext'] as String);
      final macBytes = base64Decode(envelope['mac'] as String);

      if (salt.length != 16 ||
          nonce.length != 12 ||
          macBytes.length != 16 ||
          ciphertext.isEmpty) {
        throw const FormatException('Data enkripsi backup tidak lengkap.');
      }

      final key = await _kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );

      final secretBox = SecretBox(
        ciphertext,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final clearBytes = await _cipher.decrypt(
        secretBox,
        secretKey: key,
      );

      final decodedBackup = jsonDecode(utf8.decode(clearBytes));

      if (decodedBackup is! Map<String, dynamic>) {
        throw const FormatException('Isi backup bukan objek JSON.');
      }

      return decodedBackup;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Backup gagal dibuka. Password salah atau file telah berubah.',
      );
    }
  }
}
