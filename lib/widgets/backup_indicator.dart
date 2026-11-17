import 'dart:async';

import 'package:flutter/material.dart';

import '../services/backup_status.dart';

/// Dua bulatan status di AppBar: ikon HP = backup lokal, ikon awan = Google
/// Drive. Merah/biru bergantian = belum di-backup. Hijau = sudah di-backup.
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
    BackupStatus.instance.localDirty.addListener(_onChanged);
    BackupStatus.instance.driveDirty.addListener(_onChanged);
    _syncTimer();
  }

  @override
  void dispose() {
    BackupStatus.instance.localDirty.removeListener(_onChanged);
    BackupStatus.instance.driveDirty.removeListener(_onChanged);
    _timer?.cancel();
    super.dispose();
  }

  bool get _anyDirty =>
      BackupStatus.instance.localDirty.value == true ||
      BackupStatus.instance.driveDirty.value == true;

  void _onChanged() {
    _syncTimer();
    if (mounted) setState(() {});
  }

  void _syncTimer() {
    if (_anyDirty && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
        if (mounted) setState(() => _alt = !_alt);
      });
    } else if (!_anyDirty && _timer != null) {
      _timer!.cancel();
      _timer = null;
      _alt = false;
    }
  }

  String _describe(bool? state) {
    if (state == null) return 'belum diketahui';
    return state ? 'ada perubahan belum di-backup' : 'sudah di-backup';
  }

  Color _colorFor(bool? state) {
    if (state == null) return Colors.grey;
    if (state) return _alt ? Colors.blue : Colors.red;
    return Colors.green;
  }

  Widget _item(IconData icon, bool? state) {
    final color = _colorFor(state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = BackupStatus.instance.localDirty.value;
    final drive = BackupStatus.instance.driveDirty.value;

    // Status belum diketahui: jangan tampilkan apa pun supaya tidak salah.
    if (local == null && drive == null) return const SizedBox.shrink();

    return Tooltip(
      message: 'Backup lokal: ${_describe(local)}\n'
          'Backup Google Drive: ${_describe(drive)}',
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _item(Icons.smartphone, local),
              const SizedBox(width: 10),
              _item(Icons.cloud_outlined, drive),
            ],
          ),
        ),
      ),
    );
  }
}
