import 'models.dart';

const _bulan = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// 15000 -> "Rp 15.000"
String rupiah(int value) {
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}Rp $buf';
}

/// DateTime(2026, 11, 5) -> "5 Nov 2026"
String tglJam(DateTime d) {
  if (d.hour == 0 && d.minute == 0 && d.second == 0 && d.millisecond == 0) {
    return tgl(d);
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}-${two(d.month)}-${d.year} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String tgl(DateTime d) => '${d.day} ${_bulan[d.month - 1]} ${d.year}';

String statusText(CustomerSummary s, [DateTime? now]) {
  final today = dateOnly(now ?? DateTime.now());
  switch (s.status(now)) {
    case DebtStatus.lunas:
      return 'Lunas';
    case DebtStatus.telat:
      final days = today.difference(dateOnly(s.nextDue!)).inDays;
      return 'Telat $days hari';
    case DebtStatus.mendekati:
      final days = dateOnly(s.nextDue!).difference(today).inDays;
      return days == 0 ? 'Jatuh tempo hari ini' : 'Jatuh tempo $days hari lagi';
    case DebtStatus.lancar:
      return s.nextDue == null ? 'Utang berjalan' : 'Tempo ${tgl(s.nextDue!)}';
  }
}

/// Ubah nomor lokal ke format internasional tanpa plus untuk wa.me.
/// "0812-3456-789" -> "628123456789". Mengembalikan null jika kosong.
String? normalizePhone(String raw) {
  final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('62')) return d;
  if (d.startsWith('0')) return '62${d.substring(1)}';
  if (d.startsWith('8')) return '62$d';
  return d;
}

/// Tautan WhatsApp. Tanpa nomor, WhatsApp membiarkan pengguna memilih kontak.
Uri waUri(String phone, String text) {
  final n = normalizePhone(phone);
  final encoded = Uri.encodeComponent(text);
  return Uri.parse('https://wa.me/${n ?? ''}?text=$encoded');
}

String _line(Txn t) {
  final sign = t.type == TxnType.utang ? '+' : '-';
  final label = t.type == TxnType.utang ? 'utang' : 'bayar';
  final note = t.note.trim().isEmpty ? '' : ' (${t.note.trim()})';
  return '${tglJam(t.date)}: $label $sign${rupiah(t.amount)}$note';
}

List<Txn> _newestFirst(List<Txn> txns) =>
    [...txns]..sort((a, b) => b.date.compareTo(a.date));

/// Pesan tagih yang sopan, siap kirim lewat WhatsApp.
String buildReminder({
  required String name,
  required int balance,
  DateTime? due,
  required List<Txn> txns,
}) {
  final b = StringBuffer()
    ..writeln('Halo $name, mohon maaf mengganggu 🙏')
    ..writeln(
        'Ini pengingat ramah dari warung: sisa utang Anda saat ini ${rupiah(balance)}.');
  if (due != null) b.writeln('Jatuh tempo: ${tgl(due)}.');
  final recent = _newestFirst(txns);
  if (recent.isNotEmpty) {
    b.writeln('\nRincian terakhir:');
    for (final t in recent) {
      b.writeln('- ${_line(t)}');
    }
  }
  b.write('\nKalau sudah ada rezekinya, ditunggu ya. Terima kasih banyak!');
  return b.toString();
}

/// Pesan bukti pelunasan untuk satu siklus utang yang telah ditutup.
String buildSettlementReceipt({
  required String name,
  required List<Txn> txns,
}) {
  final sorted = [...txns]..sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : (a.id ?? 0).compareTo(b.id ?? 0);
  });

  final totalDebt = sorted
      .where((t) => t.type == TxnType.utang)
      .fold<int>(0, (sum, t) => sum + t.amount);
  final totalPaid = sorted
      .where((t) => t.type == TxnType.bayar)
      .fold<int>(0, (sum, t) => sum + t.amount);

  final b = StringBuffer()
    ..writeln('BUKTI PELUNASAN')
    ..writeln('Nama: $name')
    ..writeln('Waktu: ${tglJam(DateTime.now())}')
    ..writeln('Status: LUNAS')
    ..writeln('Total utang: ${rupiah(totalDebt)}')
    ..writeln('Total pembayaran: ${rupiah(totalPaid)}')
    ..writeln('')
    ..writeln('Rincian transaksi:');

  for (final t in sorted) {
    b.writeln('- ${_line(t)}');
  }

  b.writeln('');
  b.write('Terima kasih sudah menyelesaikan pembayaran 🙏');
  return b.toString();
}

/// Rekap lengkap satu pelanggan sebagai teks.
String buildRecap({
  required String name,
  required int balance,
  required List<Txn> txns,
}) {
  final b = StringBuffer()
    ..writeln('REKAP UTANG: $name')
    ..writeln('Sisa utang: ${rupiah(balance)}')
    ..writeln('Per tanggal: ${tgl(DateTime.now())}')
    ..writeln('');
  final sorted = [...txns]..sort((a, b) => a.date.compareTo(b.date));
  for (final t in sorted) {
    b.writeln(_line(t));
  }
  return b.toString().trimRight();
}
