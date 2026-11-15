import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

class GoogleDriveService {
  GoogleDriveService._();

  static final GoogleDriveService instance = GoogleDriveService._();

  static const String _serverClientId =
      '83176740993-ughbfdiak2v3mq31prsfpae7pffkaku7.apps.googleusercontent.com';

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/drive.file',
  ];

  static const String _backupFormat =
      'buku_utang_warung_encrypted_backup';

  static const int _backupVersion = 1;
  static const int _maximumBackupBytes = 100 * 1024 * 1024;

  final GoogleSignIn _google = GoogleSignIn.instance;
  Future<void>? _initialization;
  GoogleSignInAccount? _account;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;

  final StreamController<GoogleSignInAccount?> _accountChanges =
      StreamController<GoogleSignInAccount?>.broadcast();

  GoogleSignInAccount? get account => _account;
  Stream<GoogleSignInAccount?> get accountChanges =>
      _accountChanges.stream;

  void _setAccount(GoogleSignInAccount? account) {
    _account = account;
    _accountChanges.add(account);
  }

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    await _google.initialize(serverClientId: _serverClientId);

    _authSubscription ??= _google.authenticationEvents.listen(
      (event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _restoreDiagnostic = 'AUTH_EVENT_SIGN_IN';
          _setAccount(event.user);
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          _restoreDiagnostic = 'AUTH_EVENT_SIGN_OUT';
          _setAccount(null);
        }
      },
      onError: (Object error, StackTrace stack) {
        _accountChanges.addError(error, stack);
      },
    );
  }

  String _restoreDiagnostic = 'BELUM_DIPERIKSA';

  String get restoreDiagnostic => _restoreDiagnostic;

  Future<GoogleSignInAccount?> restoreAccount() async {
    _restoreDiagnostic = 'INITIALIZING';
    await initialize();

    if (_account != null) {
      _restoreDiagnostic = 'ACCOUNT_ALREADY_AVAILABLE';
      return _account;
    }

    _restoreDiagnostic = 'ATTEMPTING_LIGHTWEIGHT_AUTH';

    try {
      final attempt = _google.attemptLightweightAuthentication(
        reportAllExceptions: true,
      );

      if (attempt == null) {
        _restoreDiagnostic = 'NO_FUTURE_RETURNED';
        return null;
      }

      final restored = await attempt;

      if (restored == null) {
        _restoreDiagnostic = 'FUTURE_RETURNED_NULL';
        return _account;
      }

      _setAccount(restored);
      _restoreDiagnostic = 'LIGHTWEIGHT_RESTORED';
      return _account;
    } catch (e) {
      _restoreDiagnostic = 'ERROR ${e.runtimeType}: $e';
      rethrow;
    }
  }

  Future<T> _withDriveApi<T>(
    Future<T> Function(drive.DriveApi api) action,
  ) async {
    final currentAccount = await restoreAccount();

    if (currentAccount == null) {
      throw StateError('Hubungkan akun Google Drive terlebih dahulu.');
    }

    final authorizationClient = currentAccount.authorizationClient;
    final authorization =
        await authorizationClient.authorizationForScopes(_scopes) ??
        await authorizationClient.authorizeScopes(_scopes);

    final client = authorization.authClient(scopes: _scopes);

    try {
      final api = drive.DriveApi(client);
      return await action(api);
    } finally {
      client.close();
    }
  }

  void _validateEncryptedFile(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > _maximumBackupBytes) {
      throw const FormatException('Ukuran backup tidak valid.');
    }

    try {
      final decoded = jsonDecode(utf8.decode(bytes));

      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != _backupFormat ||
          decoded['version'] != _backupVersion ||
          decoded['cipher'] != 'AES-256-GCM' ||
          decoded['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          decoded['iterations'] != 310000 ||
          decoded['salt'] is! String ||
          decoded['nonce'] is! String ||
          decoded['ciphertext'] is! String ||
          decoded['mac'] is! String) {
        throw const FormatException(
          'File bukan backup terenkripsi Buku Utang Warung.',
        );
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Isi file backup tidak valid.');
    }
  }

  Future<drive.File> uploadEncryptedBackup(
    List<int> encryptedBytes,
  ) async {
    _validateEncryptedFile(encryptedBytes);

    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;

    return _withDriveApi((api) async {
      final metadata = drive.File()
        ..name = 'backup_buku_utang_$timestamp.buwbackup'
        ..mimeType = 'application/octet-stream'
        ..appProperties = {
          'app': 'buku_utang_warung',
          'format': 'encrypted_backup',
          'version': '1',
        };

      final media = drive.Media(
        Stream<List<int>>.value(encryptedBytes),
        encryptedBytes.length,
      );

      final uploaded = await api.files.create(
        metadata,
        uploadMedia: media,
        $fields: 'id,name,mimeType,size,createdTime',
      );

      if (uploaded.id == null) {
        throw StateError('Upload selesai tetapi ID file tidak ditemukan.');
      }

      return uploaded;
    });
  }

  Future<List<drive.File>> listEncryptedBackups() async {
    return _withDriveApi((api) async {
      final results = <drive.File>[];
      String? pageToken;

      do {
        final response = await api.files.list(
          q: "trashed = false and "
              "appProperties has { key='app' and "
              "value='buku_utang_warung' }",
          spaces: 'drive',
          pageSize: 100,
          pageToken: pageToken,
          orderBy: 'createdTime desc',
          $fields: 'nextPageToken,files(id,name,mimeType,size,createdTime)',
        );

        results.addAll(response.files ?? <drive.File>[]);
        pageToken = response.nextPageToken;
      } while (pageToken != null);

      return results;
    });
  }

  Future<Uint8List> downloadEncryptedBackup(String fileId) async {
    if (fileId.trim().isEmpty) {
      throw ArgumentError('ID file backup kosong.');
    }

    return _withDriveApi((api) async {
      final response = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );

      if (response is! drive.Media) {
        throw StateError('Google Drive tidak mengembalikan isi file.');
      }

      final builder = BytesBuilder(copy: false);

      await for (final chunk in response.stream) {
        builder.add(chunk);

        if (builder.length > _maximumBackupBytes) {
          throw const FormatException(
            'File backup melebihi batas ukuran 100 MB.',
          );
        }
      }

      final bytes = builder.takeBytes();
      _validateEncryptedFile(bytes);

      return bytes;
    });
  }

  Future<String> connectAndTest() async {
    await initialize();

    if (!_google.supportsAuthenticate()) {
      throw Exception('Metode login tidak didukung pada perangkat ini.');
    }

    final account = await _google.authenticate();
    _setAccount(account);

    final authorizationClient = account.authorizationClient;
    final authorization =
        await authorizationClient.authorizationForScopes(_scopes) ??
        await authorizationClient.authorizeScopes(_scopes);

    final client = authorization.authClient(scopes: _scopes);

    try {
      final api = drive.DriveApi(client);

      await api.files.list(
        pageSize: 1,
        $fields: 'files(id,name)',
      );
    } finally {
      client.close();
    }

    return account.email;
  }

  Future<void> signOut() async {
    await initialize();
    await _google.signOut();
    _setAccount(null);
  }

  Future<String> switchAccount() async {
    await signOut();
    return connectAndTest();
  }
}
