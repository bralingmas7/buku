import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Melacak apakah ada perubahan data yang belum di-backup ke Google Drive.
///
/// [dirty]: null = belum diketahui, true = ada perubahan belum di-backup,
/// false = data sudah di-backup.
class BackupStatus {
  BackupStatus._();

  static final BackupStatus instance = BackupStatus._();

  static const String _dirtyKey = 'backup_dirty';

  final ValueNotifier<bool?> dirty = ValueNotifier<bool?>(null);

  bool _loaded = false;
  int _revision = 0;

  /// Naik setiap data berubah. Dipakai agar perubahan yang terjadi saat
  /// upload berlangsung tidak ikut dianggap sudah ter-backup.
  int get revision => _revision;

  /// Dipanggil sekali saat app dibuka. Panggilan berikutnya diabaikan.
  Future<void> load({required bool hasData}) async {
    if (_loaded) return;
    _loaded = true;

    try {
      final stored = await SharedPreferencesAsync().getBool(_dirtyKey);

      // Pertama kali: kalau sudah ada data tapi belum pernah di-backup,
      // anggap belum ter-backup. Kalau masih kosong, anggap aman.
      final value = stored ?? hasData;

      if (dirty.value == null) dirty.value = value;
      if (stored == null) await _persist(value);
    } catch (e) {
      debugPrint('Gagal memuat status backup: $e');
      dirty.value ??= hasData;
    }
  }

  void markDirty() {
    _revision++;
    dirty.value = true;
    unawaited(_persist(true));
  }

  /// Tandai sudah ter-backup, hanya jika data tidak berubah sejak [revision]
  /// dicatat (sebelum backup dibuat).
  Future<void> markBackedUp(int revision) async {
    if (revision != _revision) return;
    dirty.value = false;
    await _persist(false);
  }

  Future<void> _persist(bool value) async {
    try {
      await SharedPreferencesAsync().setBool(_dirtyKey, value);
    } catch (e) {
      debugPrint('Gagal menyimpan status backup: $e');
    }
  }
}
