import 'dart:async';

import 'package:flutter/material.dart';

import '../services/backup_status.dart';

/// Bulatan status backup untuk AppBar.
/// Merah/biru bergantian = belum di-backup. Hijau = sudah di-backup.
class BackupIndicator extends StatefulWidget {
  const BackupIndicator({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  State<BackupIndicator> createState() => _BackupIndicatorState();
}

class _BackupIndicatorState extends State<BackupIndicator> {
  Timer? _timer;
  bool _alt = false;

  @override
  void initState() {
    super.initState();
    BackupStatus.instance.dirty.addListener(_onChanged);
    _syncTimer();
  }

  @override
  void dispose() {
    BackupStatus.instance.dirty.removeListener(_onChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onChanged() {
    _syncTimer();
    if (mounted) setState(() {});
  }

  void _syncTimer() {
    final isDirty = BackupStatus.instance.dirty.value == true;

    if (isDirty && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
        if (mounted) setState(() => _alt = !_alt);
      });
    } else if (!isDirty && _timer != null) {
      _timer!.cancel();
      _timer = null;
      _alt = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = BackupStatus.instance.dirty.value;

    // Status belum diketahui: jangan tampilkan apa pun supaya tidak salah.
    if (state == null) return const SizedBox.shrink();

    final Color color = state
        ? (_alt ? Colors.blue : Colors.red)
        : Colors.green;

    return IconButton(
      tooltip: state
          ? 'Ada perubahan yang belum di-backup ke Google Drive'
          : 'Data sudah di-backup ke Google Drive',
      onPressed: widget.onTap,
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
