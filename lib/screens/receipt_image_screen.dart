import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/shop_message_settings.dart';
import '../utils.dart';

class ReceiptImageScreen extends StatefulWidget {
  final Customer customer;
  final List<Txn> txns;
  final int balance;
  final ShopMessageSettings shopSettings;
  final bool settlement;

  const ReceiptImageScreen({
    super.key,
    required this.customer,
    required this.txns,
    required this.balance,
    required this.shopSettings,
    required this.settlement,
  });

  @override
  State<ReceiptImageScreen> createState() => _ReceiptImageScreenState();
}

class _ReceiptImageScreenState extends State<ReceiptImageScreen> {
  final GlobalKey _imageKey = GlobalKey();
  Uint8List? _pngBytes;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  String get _fileName {
    final safeName = widget.customer.name
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final kind = widget.settlement ? 'pelunasan' : 'rekap';
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return '${kind}_${safeName}_$stamp.png';
  }

  Future<void> _capture() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _imageKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) {
        throw Exception('Pratinjau gambar belum siap.');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw Exception('Gagal membuat data PNG.');
        if (!mounted) return;
        setState(() => _pngBytes = data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyiapkan PNG: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    final bytes = _pngBytes;
    if (bytes == null || _working) return;

    setState(() => _working = true);
    try {
      await Gal.putImageBytes(
        bytes,
        name: _fileName.replaceAll('.png', ''),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PNG berhasil disimpan ke galeri.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan PNG: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _share() async {
    final bytes = _pngBytes;
    if (bytes == null || _working) return;

    setState(() => _working = true);
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'image/png',
            name: _fileName,
          ),
        ],
        fileNameOverrides: [_fileName],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membagikan PNG: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.txns]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : (a.id ?? 0).compareTo(b.id ?? 0);
      });

    final totalDebt = sorted
        .where((t) => t.type == TxnType.utang)
        .fold<int>(0, (sum, t) => sum + t.amount);
    final totalPaid = sorted
        .where((t) => t.type == TxnType.bayar)
        .fold<int>(0, (sum, t) => sum + t.amount);

    final settings = widget.shopSettings;
    final isSettlement = widget.settlement;

    return Scaffold(
      appBar: AppBar(
        title: Text(isSettlement ? 'Bukti Pelunasan PNG' : 'Rekap PNG'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: RepaintBoundary(
                  key: _imageKey,
                  child: Container(
                    width: 360,
                    padding: const EdgeInsets.all(22),
                    color: Colors.white,
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                        height: 1.45,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (settings.header.trim().isNotEmpty) ...[
                            Text(
                              settings.header.trim(),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (settings.shopName.trim().isNotEmpty)
                            Text(
                              settings.shopName.trim(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          const SizedBox(height: 12),
                          const Divider(color: Colors.black54, thickness: 1.5),
                          Text(
                            isSettlement ? 'BUKTI PELUNASAN' : 'REKAP TRANSAKSI',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _infoRow('Nama pelanggan', widget.customer.name),
                          _infoRow('Tanggal cetak', tglJam(DateTime.now())),
                          if (widget.customer.phone.trim().isNotEmpty)
                            _infoRow('Telepon', widget.customer.phone),
                          const Divider(color: Colors.black26),
                          if (isSettlement) ...[
                            _infoRow('Status', 'LUNAS'),
                            _infoRow('Total utang', rupiah(totalDebt)),
                            _infoRow('Total pembayaran', rupiah(totalPaid)),
                          ] else ...[
                            _infoRow(
                              widget.balance < 0
                                  ? 'Piutang pelanggan'
                                  : 'Sisa utang',
                              rupiah(widget.balance),
                            ),
                            _infoRow('Jumlah transaksi', '${sorted.length}'),
                          ],
                          const SizedBox(height: 14),
                          const Text(
                            'RINCIAN TRANSAKSI',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Divider(color: Colors.black54),
                          if (sorted.isEmpty)
                            const Text('Belum ada transaksi.')
                          else
                            for (final txn in sorted)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            txn.type == TxnType.utang
                                                ? 'UTANG'
                                                : 'PEMBAYARAN',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(tglJam(txn.date)),
                                          if (txn.note.trim().isNotEmpty)
                                            Text(txn.note.trim()),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${txn.type == TxnType.utang ? '+' : '-'}${rupiah(txn.amount)}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          const Divider(color: Colors.black54),
                          if (isSettlement)
                            const Text(
                              'Pembayaran telah menyelesaikan siklus utang ini.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            )
                          else
                            Text(
                              widget.balance < 0
                                  ? 'Saldo kredit pelanggan: ${rupiah(widget.balance.abs())}'
                                  : widget.balance == 0
                                      ? 'Status: LUNAS'
                                      : 'Sisa utang: ${rupiah(widget.balance)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          const SizedBox(height: 18),
                          Text(
                            settings.footer.trim().isNotEmpty
                                ? settings.footer.trim()
                                : 'Terima kasih.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Dicetak dari Buku Utang Warung',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pngBytes == null || _working ? null : _save,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Simpan PNG'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pngBytes == null || _working ? null : _share,
                      icon: const Icon(Icons.share),
                      label: const Text('Bagikan / Cetak'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_pngBytes == null)
            const LinearProgressIndicator(),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
