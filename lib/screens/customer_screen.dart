import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db.dart';
import '../dialogs.dart';
import '../models.dart';
import '../status_style.dart';
import '../utils.dart';

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
    final txn = await showTxnForm(
      context,
      customer: c,
      type: type,
      balance: computeBalance(_txns),
    );
    if (txn == null) return;
    await AppDb.instance.insertTxn(txn);
    await _load();
    if (mounted) {
      _snack(type == TxnType.utang ? 'Utang dicatat' : 'Pembayaran dicatat');
    }
  }

  Future<void> _deleteTxn(Txn t) async {
    final ok = await confirmDialog(
      context,
      title: 'Hapus catatan?',
      message: '${t.type == TxnType.utang ? 'Utang' : 'Pembayaran'} '
          '${rupiah(t.amount)} tanggal ${tgl(t.date)} akan dihapus.',
    );
    if (!ok) return;
    await AppDb.instance.deleteTxn(t.id!);
    await _load();
  }

  Future<void> _tagih() async {
    final c = _customer!;
    final msg = buildReminder(
      name: c.name,
      balance: computeBalance(_txns),
      due: nextDueDate(_txns),
      txns: _txns,
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
                case 'recap':
                  _copyRecap();
                case 'delete':
                  _deleteCustomer();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Ubah data')),
              PopupMenuItem(value: 'recap', child: Text('Salin rekap')),
              PopupMenuItem(value: 'delete', child: Text('Hapus pelanggan')),
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
                  Text('Sisa utang', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    rupiah(summary.balance),
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
      tgl(txn.date),
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
