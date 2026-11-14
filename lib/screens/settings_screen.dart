import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db.dart';
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
                  const SizedBox(height: 8),
                  const Text(
                    'Tahap ini hanya menguji login dan akses Drive. '
                    'Belum ada file yang diunggah atau dihapus.',
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
