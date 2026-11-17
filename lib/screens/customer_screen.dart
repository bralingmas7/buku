import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db.dart';
import '../dialogs.dart';
import '../models.dart';
import '../status_style.dart';
import '../utils.dart';
import '../services/shop_message_settings.dart';
import 'receipt_image_screen.dart';

class CustomerScreen extends StatefulWidget {
  final int customerId;
  const CustomerScreen({super.key, required this.customerId});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  Customer? _customer;
  List<Txn> _txns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final c = await db.customer(widget.customerId);
    final t = await db.txnsFor(widget.customerId);
    if (!mounted) return;
    if (c == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _customer = c;
      _txns = t;
      _loading = false;
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addTxn(TxnType type) async {
    final c = _customer!;
    final oldBalance = computeBalance(_txns);

    final txn = await showTxnForm(
      context,
      customer: c,
      type: type,
      balance: oldBalance,
    );
    if (txn == null) return;

    await AppDb.instance.insertTxn(txn);
    await _load();

    if (!mounted) return;

    final newBalance = computeBalance(_txns);
    _snack(type == TxnType.utang ? 'Utang dicatat' : 'Pembayaran dicatat');

    if (type == TxnType.bayar && oldBalance > 0 && newBalance == 0) {
      await _sendSettlementReceipt();
    }
  }

  Future<void> _sendSettlementReceipt() async {
    final c = _customer!;
    final cycle = latestClosedDebtCycle(_txns);
    if (cycle.isEmpty) return;

    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Utang sudah lunas'),
        content: const Text(
          'Saldo pelanggan sudah lunas. Kirim bukti pelunasan '
          'beserta seluruh transaksi dalam siklus ini melalui WhatsApp?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kirim WhatsApp'),
          ),
        ],
      ),
    );

    if (send != true || !mounted) return;

    final messageSettings = await ShopMessageSettings.load();
    final msg = buildSettlementReceipt(
      name: c.name,
      txns: cycle,
      shopName: messageSettings.shopName,
      header: messageSettings.header,
      footer: messageSettings.footer,
    );
    var opened = false;

    try {
      opened = await launchUrl(
        waUri(c.phone, msg),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }

    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: msg));
      _snack('WhatsApp tidak bisa dibuka. Bukti pelunasan disalin.');
    }
  }

  Future<void> _deleteTxn(Txn t) async {
    final ok = await confirmDialog(
      context,
      title: 'Hapus catatan?',
      message: '${t.type == TxnType.utang ? 'Utang' : 'Pembayaran'} '
          '${rupiah(t.amount)} tanggal ${tglJam(t.date)} akan dihapus.',
    );
    if (!ok) return;
    await AppDb.instance.deleteTxn(t.id!);
    await _load();
  }

  Future<void> _tagih() async {
    final c = _customer!;
    final balance = computeBalance(_txns);
    if (balance <= 0) {
      _snack('Tidak ada utang yang perlu ditagih.');
      return;
    }

    final messageSettings = await ShopMessageSettings.load();
    final cycle = activeDebtCycle(_txns);
    final msg = buildReminder(
      name: c.name,
      balance: balance,
      due: nextDueDate(cycle),
      txns: cycle,
      shopName: messageSettings.shopName,
      header: messageSettings.header,
      footer: messageSettings.footer,
    );
    bool ok;
    try {
      ok = await launchUrl(waUri(c.phone, msg),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: msg));
      _snack('WhatsApp tidak bisa dibuka. Pesan disalin, tempel manual ya.');
    }
  }

  Future<void> _copyRecap() async {
    final c = _customer!;
    await Clipboard.setData(ClipboardData(
      text: buildRecap(
        name: c.name,
        balance: computeBalance(_txns),
        txns: _txns,
      ),
    ));
    if (mounted) _snack('Rekap disalin');
  }

  Future<void> _openPng({required bool settlement}) async {
    final c = _customer!;
    final selectedTxns =
        settlement ? latestClosedDebtCycle(_txns) : List<Txn>.from(_txns);

    if (settlement && selectedTxns.isEmpty) {
      _snack('Belum ada siklus utang yang lunas.');
      return;
    }

    final settings = await ShopMessageSettings.load();
    if (!mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptImageScreen(
          customer: c,
          txns: selectedTxns,
          balance: computeBalance(_txns),
          shopSettings: settings,
          settlement: settlement,
        ),
      ),
    );
  }

  Future<void> _edit() async {
    final updated = await showCustomerForm(context, existing: _customer);
    if (updated == null) return;
    await AppDb.instance.updateCustomer(updated);
    await _load();
  }

  Future<void> _deleteCustomer() async {
    final c = _customer!;
    final ok = await confirmDialog(
      context,
      title: 'Hapus pelanggan?',
      message:
          '${c.name} beserta semua catatan utangnya akan dihapus permanen.',
    );
    if (!ok) return;
    await AppDb.instance.deleteCustomer(c.id!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _customer == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final c = _customer!;
    final summary = CustomerSummary(
      customer: c,
      balance: computeBalance(_txns),
      nextDue: nextDueDate(_txns),
    );
    final history = [..._txns]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  _edit();
                  break;
                case 'recap':
                  _copyRecap();
                  break;
                case 'recap_png':
                  _openPng(settlement: false);
                  break;
                case 'settlement_png':
                  _openPng(settlement: true);
                  break;
                case 'delete':
                  _deleteCustomer();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Ubah data')),
              const PopupMenuItem(value: 'recap', child: Text('Salin rekap')),
              const PopupMenuItem(
                value: 'recap_png',
                child: Text('Simpan rekap sebagai PNG'),
              ),
              if (latestClosedDebtCycle(_txns).isNotEmpty)
                const PopupMenuItem(
                  value: 'settlement_png',
                  child: Text('Bukti pelunasan PNG'),
                ),
              const PopupMenuItem(value: 'delete', child: Text('Hapus pelanggan')),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: history.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) return _Header(summary: summary, onAdd: _addTxn, onTagih: _tagih);
          final t = history[i - 1];
          return _TxnTile(txn: t, onLongPress: () => _deleteTxn(t));
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final CustomerSummary summary;
  final Future<void> Function(TxnType) onAdd;
  final VoidCallback onTagih;
  const _Header({
    required this.summary,
    required this.onAdd,
    required this.onTagih,
  });

  @override
  Widget build(BuildContext context) {
    final c = summary.customer;
    final status = summary.status();
    final color = statusColor(status);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status == DebtStatus.piutang
                        ? 'Piutang pelanggan'
                        : 'Sisa utang',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rupiah(summary.balance.abs()),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: status == DebtStatus.lunas ? null : color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(statusText(summary),
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w600)),
                  if (c.creditLimit > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Batas utang ${rupiah(c.creditLimit)}'
                      '${summary.overLimit ? ' (terlewati)' : ''}',
                      style: TextStyle(
                        color: summary.overLimit ? kMerah : null,
                        fontWeight:
                            summary.overLimit ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                  if (c.phone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('WhatsApp: ${c.phone}'),
                  ],
                  if (c.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(c.note, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onAdd(TxnType.utang),
                  icon: const Icon(Icons.add),
                  label: const Text('Utang baru'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: summary.balance > 0
                      ? () => onAdd(TxnType.bayar)
                      : null,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Bayar'),
                ),
              ),
            ],
          ),
          if (summary.balance > 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onTagih,
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Tagih lewat WhatsApp'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('Riwayat', style: theme.textTheme.titleMedium),
          Text('Tahan lama pada catatan untuk menghapus.',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final Txn txn;
  final VoidCallback onLongPress;
  const _TxnTile({required this.txn, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final isDebt = txn.type == TxnType.utang;
    final color = isDebt ? kMerah : kHijau;
    final subtitle = [
      tglJam(txn.date),
      if (isDebt && txn.dueDate != null) 'tempo ${tgl(txn.dueDate!)}',
    ].join(' • ');

    return ListTile(
      onLongPress: onLongPress,
      leading: CircleAvatar(
        backgroundColor: color.withAlpha(35),
        foregroundColor: color,
        child: Icon(isDebt ? Icons.arrow_upward : Icons.arrow_downward),
      ),
      title: Text(txn.note.isEmpty
          ? (isDebt ? 'Utang' : 'Pembayaran')
          : txn.note),
      subtitle: Text(subtitle),
      trailing: Text(
        '${isDebt ? '+' : '-'}${rupiah(txn.amount)}',
        style: TextStyle(
            color: color, fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }
}
