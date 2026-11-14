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

  final GoogleSignIn _google = GoogleSignIn.instance;
  Future<void>? _initialization;
  GoogleSignInAccount? _account;

  GoogleSignInAccount? get account => _account;

  Future<void> initialize() {
    return _initialization ??= _google.initialize(
      serverClientId: _serverClientId,
    );
  }

  Future<GoogleSignInAccount?> restoreAccount() async {
    await initialize();

    // Jika layanan masih hidup, gunakan akun yang sudah terautentikasi.
    if (_account != null) return _account;

    // Setelah aplikasi dimulai ulang, coba pulihkan sesi sebelumnya.
    final attempt = _google.attemptLightweightAuthentication();

    if (attempt == null) return null;

    _account = await attempt;
    return _account;
  }

  Future<String> connectAndTest() async {
    await initialize();

    if (!_google.supportsAuthenticate()) {
      throw Exception('Metode login tidak didukung pada perangkat ini.');
    }

    final account = await _google.authenticate();
    _account = account;

    final authorization =
        await account.authorizationClient.authorizeScopes(_scopes);

    final client = authorization.authClient(scopes: _scopes);

    try {
      final api = drive.DriveApi(client);

      // Tes akses baca. Tidak mengubah atau menghapus file Drive.
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
    _account = null;
  }

  Future<String> switchAccount() async {
    await signOut();
    return connectAndTest();
  }
}
