import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

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
          const Card(
            child: ListTile(
              leading: Icon(Icons.cloud_outlined),
              title: Text('Google Drive'),
              subtitle: Text(
                'Login Google dan backup otomatis akan ditambahkan '
                'setelah fitur backup lokal selesai diuji.',
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
