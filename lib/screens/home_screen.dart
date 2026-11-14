import 'package:flutter/material.dart';

import '../db.dart';
import '../dialogs.dart';
import '../models.dart';
import '../status_style.dart';
import '../utils.dart';
import 'customer_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<CustomerSummary> _items = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final customers = await db.customers();
    final txns = await db.allTxns();
    final list = buildSummaries(customers, txns)
      ..sort((a, b) {
        final byBalance = b.balance.compareTo(a.balance);
        return byBalance != 0
            ? byBalance
            : a.customer.name
                .toLowerCase()
                .compareTo(b.customer.name.toLowerCase());
      });
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<Customer?> _createCustomer() async {
    final c = await showCustomerForm(context);
    if (c == null) return null;
    final id = await AppDb.instance.insertCustomer(c);
    return c.copyWith(id: id);
  }

  Future<void> _addCustomerOnly() async {
    final c = await _createCustomer();
    if (c != null) await _load();
  }

  /// Alur cepat: pilih pelanggan -> isi nominal -> simpan.
  Future<void> _quickDebt() async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PickCustomerSheet(items: _items),
    );
    if (picked == null || !mounted) return;

    Customer? customer;
    var balance = 0;
    if (picked is CustomerSummary) {
      customer = picked.customer;
      balance = picked.balance;
    } else {
      customer = await _createCustomer();
    }
    if (customer == null || !mounted) return;

    final txn = await showTxnForm(
      context,
      customer: customer,
      type: TxnType.utang,
      balance: balance,
    );
    if (txn != null) await AppDb.instance.insertTxn(txn);
    await _load();
  }

  Future<void> _openCustomer(Customer c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerScreen(customerId: c.id!)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = _items
        .where((s) => q.isEmpty || s.customer.name.toLowerCase().contains(q))
        .toList();

    final totalPiutang =
        _items.fold<int>(0, (sum, s) => sum + (s.balance > 0 ? s.balance : 0));
    final telat =
        _items.where((s) => s.status() == DebtStatus.telat).length;
    final mendekati =
        _items.where((s) => s.status() == DebtStatus.mendekati).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buku Utang Warung'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
              await _load();
            },
          ),
          IconButton(
            tooltip: 'Pelanggan baru',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _addCustomerOnly,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _quickDebt,
        icon: const Icon(Icons.add),
        label: const Text('Utang baru'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _SummaryCard(
                  total: totalPiutang,
                  telat: telat,
                  mendekati: mendekati,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Cari pelanggan',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              _items.isEmpty
                                  ? 'Belum ada pelanggan.\nKetuk "Utang baru" untuk mulai mencatat.'
                                  : 'Tidak ada pelanggan dengan nama itu.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: visible.length,
                          itemBuilder: (_, i) => _CustomerTile(
                            summary: visible[i],
                            onTap: () => _openCustomer(visible[i].customer),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int total;
  final int telat;
  final int mendekati;
  const _SummaryCard({
    required this.total,
    required this.telat,
    required this.mendekati,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total piutang',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              rupiah(total),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Badge(label: 'Telat', count: telat, color: kMerah),
                const SizedBox(width: 12),
                _Badge(
                    label: 'Segera tempo', count: mendekati, color: kKuning),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _Badge({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('$label: $count',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final CustomerSummary summary;
  final VoidCallback onTap;
  const _CustomerTile({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = summary.status();
    final color = statusColor(status);
    final name = summary.customer.name;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withAlpha(40),
        foregroundColor: color,
        child: Text(name.characters.first.toUpperCase()),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        statusText(summary) + (summary.overLimit ? ' • Melewati batas' : ''),
        style: TextStyle(
            color: status == DebtStatus.lunas ? null : color,
            fontWeight: FontWeight.w500),
      ),
      trailing: Text(
        rupiah(summary.balance),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}
