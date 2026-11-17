import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Melacak apakah ada perubahan data yang belum di-backup, terpisah untuk
/// backup lokal (file di HP) dan Google Drive.
///
/// Nilai notifier: null = belum diketahui, true = ada perubahan belum
/// di-backup, false = sudah di-backup.
class BackupStatus {
  BackupStatus._();

  static final BackupStatus instance = BackupStatus._();

  // Kunci lama dipertahankan untuk Google Drive agar status lama tidak hilang.
  static const String _driveKey = 'backup_dirty';
  static const String _localKey = 'backup_local_dirty';

  final ValueNotifier<bool?> driveDirty = ValueNotifier<bool?>(null);
  final ValueNotifier<bool?> localDirty = ValueNotifier<bool?>(null);

  bool _loaded = false;
  int _revision = 0;

  // Semua penulisan status dijalankan berurutan agar status lama
  // tidak menimpa status terbaru ketika operasi berlangsung bersamaan.
  Future<void> _writeQueue = Future<void>.value();

  /// Naik setiap data berubah. Dipakai agar perubahan yang terjadi saat
  /// backup berlangsung tidak ikut dianggap sudah ter-backup.
  int get revision => _revision;

  /// Dipanggil sekali saat app dibuka. Panggilan berikutnya diabaikan.
  Future<void> load({required bool hasData}) async {
    if (_loaded) return;
    _loaded = true;

    try {
      final prefs = SharedPreferencesAsync();
      final drive = await prefs.getBool(_driveKey);
      final local = await prefs.getBool(_localKey);

      // Pertama kali: kalau sudah ada data tapi belum pernah di-backup,
      // anggap belum ter-backup. Kalau masih kosong, anggap aman.
      driveDirty.value ??= drive ?? hasData;
      localDirty.value ??= local ?? hasData;

      if (drive == null) await _persist(_driveKey, driveDirty.value ?? hasData);
      if (local == null) await _persist(_localKey, localDirty.value ?? hasData);
    } catch (e) {
      debugPrint('Gagal memuat status backup: $e');
      driveDirty.value ??= hasData;
      localDirty.value ??= hasData;
    }
  }

  void markDirty() {
    _revision++;
    driveDirty.value = true;
    localDirty.value = true;
    unawaited(_persist(_driveKey, true));
    unawaited(_persist(_localKey, true));
  }

  /// Tandai Google Drive sudah ter-backup, hanya jika data tidak berubah
  /// sejak [revision] dicatat (sebelum backup dibuat).
  Future<void> markDriveBackedUp(int revision) async {
    if (revision != _revision) return;
    driveDirty.value = false;
    await _persist(_driveKey, false);
  }

  /// Sama seperti [markDriveBackedUp], untuk backup file lokal.
  Future<void> markLocalBackedUp(int revision) async {
    if (revision != _revision) return;
    localDirty.value = false;
    await _persist(_localKey, false);
  }

  /// Nama lama, tetap dipakai oleh alur backup Google Drive.
  Future<void> markBackedUp(int revision) => markDriveBackedUp(revision);

  Future<void> _persist(String key, bool value) {
    final operation = _writeQueue.then((_) async {
      try {
        await SharedPreferencesAsync().setBool(key, value);
      } catch (e) {
        debugPrint('Gagal menyimpan status backup: $e');
      }
    });

    _writeQueue = operation;
    return operation;
  }
}
