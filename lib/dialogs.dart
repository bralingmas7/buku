import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'status_style.dart';
import 'utils.dart';

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String okLabel = 'Hapus',
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kMerah),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

// ---------------------------------------------------------------------------
// Form pelanggan
// ---------------------------------------------------------------------------

Future<Customer?> showCustomerForm(BuildContext context,
    {Customer? existing}) {
  return showDialog<Customer>(
    context: context,
    builder: (_) => _CustomerDialog(existing: existing),
  );
}

class _CustomerDialog extends StatefulWidget {
  final Customer? existing;
  const _CustomerDialog({this.existing});

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _limit;
  late final TextEditingController _note;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _limit = TextEditingController(
        text: (c != null && c.creditLimit > 0) ? '${c.creditLimit}' : '');
    _note = TextEditingController(text: c?.note ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _limit.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama wajib diisi');
      return;
    }
    final c = widget.existing;
    Navigator.pop(
      context,
      Customer(
        id: c?.id,
        name: name,
        phone: _phone.text.trim(),
        note: _note.text.trim(),
        creditLimit: int.tryParse(_limit.text) ?? 0,
        createdAt: c?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.existing == null ? 'Pelanggan baru' : 'Ubah pelanggan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nama',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'No. WhatsApp (opsional)',
                hintText: '08123456789',
              ),
            ),
            TextField(
              controller: _limit,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Batas utang (opsional)',
                prefixText: 'Rp ',
              ),
            ),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                hintText: 'Contoh: tetangga sebelah, gajian tiap akhir bulan',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(onPressed: _save, child: const Text('Simpan')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Form transaksi (utang baru / bayar)
// ---------------------------------------------------------------------------

Future<Txn?> showTxnForm(
  BuildContext context, {
  required Customer customer,
  required TxnType type,
  required int balance,
}) {
  return showDialog<Txn>(
    context: context,
    builder: (_) =>
        _TxnDialog(customer: customer, type: type, balance: balance),
  );
}

class _TxnDialog extends StatefulWidget {
  final Customer customer;
  final TxnType type;
  final int balance;
  const _TxnDialog({
    required this.customer,
    required this.type,
    required this.balance,
  });

  @override
  State<_TxnDialog> createState() => _TxnDialogState();
}

class _TxnDialogState extends State<_TxnDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  // 0 = tanpa tempo, 1 = 1 minggu, 2 = 2 minggu, 3 = 1 bulan, 4 = pilih tanggal
  int _dueChoice = 0;
  DateTime? _due;

  bool get _isDebt => widget.type == TxnType.utang;
  int get _value => int.tryParse(_amount.text) ?? 0;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _pickDue(int choice) {
    final today = dateOnly(DateTime.now());
    setState(() {
      _dueChoice = choice;
      switch (choice) {
        case 1:
          _due = today.add(const Duration(days: 7));
          break;
        case 2:
          _due = today.add(const Duration(days: 14));
          break;
        case 3:
          _due = DateTime(today.year, today.month + 1, today.day);
          break;
        default:
          _due = null;
      }
    });
  }

  Future<void> _pickCustomDate() async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 3)),
    );
    if (picked == null) return;
    setState(() {
      _dueChoice = 4;
      _due = dateOnly(picked);
    });
  }

  void _save() {
    if (_value <= 0) {
      setState(() => _error = 'Isi nominal dulu');
      return;
    }
    Navigator.pop(
      context,
      Txn(
        customerId: widget.customer.id!,
        type: widget.type,
        amount: _value,
        note: _note.text.trim(),
        date: DateTime.now(),
        dueDate: _isDebt ? _due : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final limit = widget.customer.creditLimit;
    final overLimit =
        _isDebt && limit > 0 && widget.balance + _value > limit;

    return AlertDialog(
      title: Text(_isDebt ? 'Utang baru' : 'Pembayaran'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.customer.name,
                style: Theme.of(context).textTheme.titleMedium),
            if (widget.balance != 0)
              Text('Sisa utang sekarang: ${rupiah(widget.balance)}',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_value > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(rupiah(_value),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            if (!_isDebt && widget.balance > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _amount.text = '${widget.balance}';
                    _error = null;
                  }),
                  child: Text('Lunas (${rupiah(widget.balance)})'),
                ),
              ),
            if (overLimit)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Melewati batas utang ${rupiah(limit)}',
                  style: const TextStyle(
                      color: kMerah, fontWeight: FontWeight.w600),
                ),
              ),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Catatan (opsional)',
                hintText: _isDebt ? 'Contoh: beras 5kg, minyak' : 'Contoh: cicil',
              ),
            ),
            if (_isDebt) ...[
              const SizedBox(height: 16),
              Text('Jatuh tempo', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Tanpa'),
                    selected: _dueChoice == 0,
                    onSelected: (_) => _pickDue(0),
                  ),
                  ChoiceChip(
                    label: const Text('1 minggu'),
                    selected: _dueChoice == 1,
                    onSelected: (_) => _pickDue(1),
                  ),
                  ChoiceChip(
                    label: const Text('2 minggu'),
                    selected: _dueChoice == 2,
                    onSelected: (_) => _pickDue(2),
                  ),
                  ChoiceChip(
                    label: const Text('1 bulan'),
                    selected: _dueChoice == 3,
                    onSelected: (_) => _pickDue(3),
                  ),
                  ChoiceChip(
                    label: Text(_dueChoice == 4 && _due != null
                        ? tgl(_due!)
                        : 'Pilih tanggal'),
                    selected: _dueChoice == 4,
                    onSelected: (_) => _pickCustomDate(),
                  ),
                ],
              ),
              if (_due != null && _dueChoice != 4)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Jatuh tempo: ${tgl(_due!)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(onPressed: _save, child: const Text('Simpan')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pilih pelanggan (untuk alur "Utang baru" cepat dari layar utama)
// ---------------------------------------------------------------------------

/// Hasil: [CustomerSummary] jika memilih pelanggan, 'new' jika ingin
/// membuat pelanggan baru, atau null jika ditutup.
class PickCustomerSheet extends StatefulWidget {
  final List<CustomerSummary> items;
  const PickCustomerSheet({super.key, required this.items});

  @override
  State<PickCustomerSheet> createState() => _PickCustomerSheetState();
}

class _PickCustomerSheetState extends State<PickCustomerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = widget.items
        .where((s) => q.isEmpty || s.customer.name.toLowerCase().contains(q))
        .toList();

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cari nama pelanggan',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_add)),
                title: const Text('Pelanggan baru'),
                onTap: () => Navigator.pop(context, 'new'),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final s = list[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            statusColor(s.status()).withAlpha(40),
                        child: Text(s.customer.name.characters.first
                            .toUpperCase()),
                      ),
                      title: Text(s.customer.name),
                      subtitle: Text(statusText(s)),
                      trailing: Text(rupiah(s.balance),
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () => Navigator.pop(context, s),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
