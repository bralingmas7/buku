enum TxnType { utang, bayar }

enum DebtStatus { lunas, lancar, mendekati, telat }

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class Customer {
  final int? id;
  final String name;
  final String phone;
  final String note;

  /// Batas utang dalam rupiah. 0 berarti tanpa batas.
  final int creditLimit;
  final DateTime createdAt;

  const Customer({
    this.id,
    required this.name,
    this.phone = '',
    this.note = '',
    this.creditLimit = 0,
    required this.createdAt,
  });

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? note,
    int? creditLimit,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      note: note ?? this.note,
      creditLimit: creditLimit ?? this.creditLimit,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'note': note,
        'credit_limit': creditLimit,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id'] as int?,
        name: m['name'] as String,
        phone: (m['phone'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        creditLimit: (m['credit_limit'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

class Txn {
  final int? id;
  final int customerId;
  final TxnType type;
  final int amount;
  final String note;
  final DateTime date;
  final DateTime? dueDate;

  const Txn({
    this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    this.note = '',
    required this.date,
    this.dueDate,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'customer_id': customerId,
        'type': type.name,
        'amount': amount,
        'note': note,
        'date': date.millisecondsSinceEpoch,
        'due_date': dueDate?.millisecondsSinceEpoch,
      };

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
        id: m['id'] as int?,
        customerId: m['customer_id'] as int,
        type: TxnType.values.byName(m['type'] as String),
        amount: m['amount'] as int,
        note: (m['note'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        dueDate: m['due_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['due_date'] as int),
      );
}

/// Sisa utang = total utang dikurangi total pembayaran.
int computeBalance(List<Txn> txns) => txns.fold<int>(
      0,
      (sum, t) => sum + (t.type == TxnType.utang ? t.amount : -t.amount),
    );

/// Jatuh tempo terdekat dari utang yang belum tertutup.
/// Pembayaran dialokasikan ke utang paling lama lebih dulu (FIFO).
DateTime? nextDueDate(List<Txn> txns) {
  var credit = txns
      .where((t) => t.type == TxnType.bayar)
      .fold<int>(0, (sum, t) => sum + t.amount);
  final debts = txns.where((t) => t.type == TxnType.utang).toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  DateTime? earliest;
  for (final d in debts) {
    if (credit >= d.amount) {
      credit -= d.amount;
      continue;
    }
    credit = 0;
    final due = d.dueDate;
    if (due != null && (earliest == null || due.isBefore(earliest))) {
      earliest = due;
    }
  }
  return earliest;
}

class CustomerSummary {
  final Customer customer;
  final int balance;
  final DateTime? nextDue;
  final DateTime? lastActivity;

  const CustomerSummary({
    required this.customer,
    required this.balance,
    this.nextDue,
    this.lastActivity,
  });

  DebtStatus status([DateTime? now]) {
    if (balance <= 0) return DebtStatus.lunas;
    final due = nextDue;
    if (due == null) return DebtStatus.lancar;
    final today = dateOnly(now ?? DateTime.now());
    final dueDay = dateOnly(due);
    if (dueDay.isBefore(today)) return DebtStatus.telat;
    if (dueDay.difference(today).inDays <= 3) return DebtStatus.mendekati;
    return DebtStatus.lancar;
  }

  bool get overLimit =>
      customer.creditLimit > 0 && balance > customer.creditLimit;
}

List<CustomerSummary> buildSummaries(
  List<Customer> customers,
  List<Txn> txns,
) {
  final byCustomer = <int, List<Txn>>{};
  for (final t in txns) {
    byCustomer.putIfAbsent(t.customerId, () => <Txn>[]).add(t);
  }
  return customers.map((c) {
    final list = byCustomer[c.id] ?? <Txn>[];
    return CustomerSummary(
      customer: c,
      balance: computeBalance(list),
      nextDue: nextDueDate(list),
      lastActivity: list.isEmpty
          ? null
          : list.map((t) => t.date).reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }).toList();
}


/// Mengurutkan transaksi berdasarkan waktu, lalu ID untuk waktu yang sama.
List<Txn> _orderedTxns(List<Txn> txns) {
  return [...txns]..sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : (a.id ?? 0).compareTo(b.id ?? 0);
  });
}

/// Transaksi pada siklus utang yang masih aktif.
List<Txn> activeDebtCycle(List<Txn> txns) {
  final cycle = <Txn>[];
  var balance = 0;

  for (final t in _orderedTxns(txns)) {
    cycle.add(t);
    balance += t.type == TxnType.utang ? t.amount : -t.amount;

    if (balance <= 0) {
      cycle.clear();
      balance = 0;
    }
  }

  return cycle;
}

/// Transaksi pada siklus terakhir yang sudah lunas.
List<Txn> latestClosedDebtCycle(List<Txn> txns) {
  final cycle = <Txn>[];
  List<Txn> latestClosed = [];
  var balance = 0;

  for (final t in _orderedTxns(txns)) {
    cycle.add(t);
    balance += t.type == TxnType.utang ? t.amount : -t.amount;

    if (balance <= 0) {
      if (cycle.any((item) => item.type == TxnType.utang)) {
        latestClosed = List<Txn>.from(cycle);
      }
      cycle.clear();
      balance = 0;
    }
  }

  return latestClosed;
}
