import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db.dart';
import '../services/backup_crypto_service.dart';
import '../services/google_drive_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  String? _googleEmail;

  @override
  void initState() {
    super.initState();

    // Pulihkan tampilan akun saat halaman Pengaturan dibuka kembali.
    _googleEmail = GoogleDriveService.instance.account?.email;
    _restoreGoogleStatus();
  }

  Future<void> _restoreGoogleStatus() async {
    try {
      final account =
          await GoogleDriveService.instance.restoreAccount();

      if (!mounted || account == null) return;

      setState(() => _googleEmail = account.email);
    } catch (e) {
      debugPrint('Pemulihan status Google gagal: $e');
    }
  }

  Future<void> _connectGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final email =
          await GoogleDriveService.instance.connectAndTest();

      if (!mounted) return;
      setState(() => _googleEmail = email);
      _message('Google Drive berhasil terhubung: $email');
    } catch (e) {
      _message('Koneksi Google gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final email =
          await GoogleDriveService.instance.switchAccount();

      if (!mounted) return;
      setState(() => _googleEmail = email);
      _message('Akun Google berhasil diganti: $email');
    } catch (e) {
      _message('Ganti akun gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logoutGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await GoogleDriveService.instance.signOut();

      if (!mounted) return;
      setState(() => _googleEmail = null);
      _message('Logout Google berhasil. Data lokal tetap aman.');
    } catch (e) {
      _message('Logout Google gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _backup() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final data = await AppDb.instance.exportBackup();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final now = DateTime.now();
      final stamp = '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';

      final result = await FilePicker.saveFile(
        dialogTitle: 'Simpan backup Buku Utang Warung',
        fileName: 'backup_buku_utang_$stamp.json',
        bytes: Uint8List.fromList(utf8.encode(json)),
        mimeType: 'application/json',
      );

      if (result != null) {
        _message('File backup berhasil disimpan.');
      }
    } catch (e) {
      _message('Backup gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();
      final decoded = jsonDecode(utf8.decode(bytes));

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Isi file JSON tidak valid');
      }

      // Periksa semua isi file sebelum meminta persetujuan penggantian data.
      AppDb.validateBackupData(decoded);

      final customerCount = (decoded['customers'] as List).length;
      final txnCount = (decoded['transactions'] as List).length;

      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pulihkan data?'),
          content: Text(
            'Data saat ini akan DIGANTI dengan isi backup.\n\n'
            'Pelanggan: $customerCount\n'
            'Transaksi: $txnCount\n\n'
            'Pastikan Anda sudah membuat backup data saat ini.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ganti dan pulihkan'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      await AppDb.instance.restoreBackup(decoded);
      _message('Restore berhasil. Data telah dipulihkan.');
    } catch (e) {
      _message('Restore gagal. Data lama tetap aman: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<String?> _askCloudPassword({required bool confirm}) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? mismatch;

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(
              confirm ? 'Buat password backup' : 'Password backup',
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Password backup',
                      helperText: 'Minimal 8 karakter',
                    ),
                    validator: (value) {
                      if ((value ?? '').runes.length < 8) {
                        return 'Password minimal 8 karakter.';
                      }
                      return null;
                    },
                  ),
                  if (confirm) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Ulangi password backup',
                      ),
                      onChanged: (_) {
                        if (mismatch != null) {
                          setDialogState(() => mismatch = null);
                        }
                      },
                    ),
                  ],
                  if (mismatch != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      mismatch!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Password ini berbeda dari password Google. '
                    'Aplikasi tidak menyimpan password ini. '
                    'Jika lupa, backup tidak dapat dipulihkan.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;

                  if (confirm &&
                      passwordController.text != confirmController.text) {
                    setDialogState(
                      () => mismatch = 'Password yang dimasukkan tidak sama.',
                    );
                    return;
                  }

                  Navigator.pop(dialogContext, passwordController.text);
                },
                child: const Text('Lanjutkan'),
              ),
            ],
          ),
        ),
      );
    } finally {
      passwordController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _cloudBackup() async {
    if (_busy || _googleEmail == null) return;

    final password = await _askCloudPassword(confirm: true);
    if (password == null || !mounted) return;

    setState(() => _busy = true);

    try {
      final data = await AppDb.instance.exportBackup();
      final encrypted =
          await BackupCryptoService.instance.encryptBackup(data, password);

      final uploaded =
          await GoogleDriveService.instance.uploadEncryptedBackup(encrypted);

      _message('Backup terenkripsi berhasil diunggah: ${uploaded.name}');
    } catch (e) {
      _message('Backup Google Drive gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cloudRestore() async {
    if (_busy || _googleEmail == null) return;

    setState(() => _busy = true);

    try {
      final files =
          await GoogleDriveService.instance.listEncryptedBackups();

      if (!mounted) return;

      if (files.isEmpty) {
        _message('Belum ada backup Buku Utang Warung di Google Drive.');
        return;
      }

      final selectedIndex = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pilih backup cloud'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < files.length; i++)
                  ListTile(
                    leading: const Icon(Icons.cloud_download_outlined),
                    title: Text(files[i].name ?? 'Backup tanpa nama'),
                    subtitle: Text(
                      files[i].createdTime?.toLocal().toString() ??
                          'Waktu tidak tersedia',
                    ),
                    onTap: () => Navigator.pop(dialogContext, i),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
          ],
        ),
      );

      if (selectedIndex == null || !mounted) return;

      final selectedFile = files[selectedIndex];
      final fileId = selectedFile.id;
      if (fileId == null || fileId.isEmpty) {
        throw StateError('ID backup Google Drive tidak tersedia.');
      }

      final password = await _askCloudPassword(confirm: false);
      if (password == null || !mounted) return;

      final encrypted =
          await GoogleDriveService.instance.downloadEncryptedBackup(fileId);

      final decoded =
          await BackupCryptoService.instance.decryptBackup(
        encrypted,
        password,
      );

      AppDb.validateBackupData(decoded);

      final customerCount = (decoded['customers'] as List).length;
      final transactionCount = (decoded['transactions'] as List).length;

      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pulihkan backup cloud?'),
          content: Text(
            'Data lokal saat ini akan DIGANTI dengan isi backup cloud.\n\n'
            'Pelanggan: $customerCount\n'
            'Transaksi: $transactionCount\n\n'
            'Pastikan Anda sudah memiliki salinan data saat ini.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Ganti dan pulihkan'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      await AppDb.instance.restoreBackup(decoded);
      _message('Restore dari Google Drive berhasil.');
    } catch (e) {
      _message('Restore Google Drive gagal. Data lokal tidak diganti: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.backup_outlined),
                  title: Text('Backup lokal'),
                  subtitle: Text(
                    'Simpan semua pelanggan dan transaksi ke file JSON.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _backup,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Buat backup'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('Pulihkan backup'),
                  subtitle: Text(
                    'Pilih file JSON. Data saat ini akan diganti setelah konfirmasi.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _restore,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Pilih file backup'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.cloud_outlined),
                    title: Text('Google Drive'),
                    subtitle: Text(
                      'Hubungkan akun Google untuk menyiapkan backup cloud.',
                    ),
                  ),
                  if (_googleEmail != null) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_circle_outlined),
                      title: const Text('Akun terhubung'),
                      subtitle: Text(_googleEmail!),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _switchGoogle,
                        icon: const Icon(Icons.switch_account),
                        label: const Text('Ganti akun Google'),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _busy ? null : _logoutGoogle,
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout Google'),
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _connectGoogle,
                        icon: const Icon(Icons.login),
                        label: const Text('Hubungkan Google Drive'),
                      ),
                    ),
                  if (_googleEmail != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _cloudBackup,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Backup ke Google Drive'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _cloudRestore,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Pulihkan dari Google Drive'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Backup cloud dienkripsi sebelum dikirim. '
                    'Gunakan password backup khusus dan ingat password tersebut '
                    'untuk memulihkan data.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 16),
          const Text(
            'Data aplikasi tetap tersimpan di perangkat. '
            'Logout akun Google nantinya tidak akan menghapus data lokal.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
