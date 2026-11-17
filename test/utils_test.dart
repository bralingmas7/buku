import 'package:flutter_test/flutter_test.dart';

import 'package:buku_utang_warung/models.dart';
import 'package:buku_utang_warung/utils.dart';

Txn utang(int amount, DateTime date, {DateTime? due}) => Txn(
      customerId: 1,
      type: TxnType.utang,
      amount: amount,
      date: date,
      dueDate: due,
    );

Txn bayar(int amount, DateTime date) =>
    Txn(customerId: 1, type: TxnType.bayar, amount: amount, date: date);

void main() {
  test('rupiah memakai pemisah titik', () {
    expect(rupiah(0), 'Rp 0');
    expect(rupiah(500), 'Rp 500');
    expect(rupiah(15000), 'Rp 15.000');
    expect(rupiah(1250000), 'Rp 1.250.000');
    expect(rupiah(-2000), '-Rp 2.000');
  });

  test('tgl memakai nama bulan Indonesia', () {
    expect(tgl(DateTime(2026, 11, 5)), '5 Nov 2026');
    expect(tgl(DateTime(2026, 8, 17)), '17 Agu 2026');
  });

  test('normalizePhone ke format internasional', () {
    expect(normalizePhone('0812-3456-789'), '628123456789');
    expect(normalizePhone('+62 812 3456 789'), '628123456789');
    expect(normalizePhone('8123456789'), '628123456789');
    expect(normalizePhone(''), isNull);
  });

  test('saldo = utang dikurangi bayar', () {
    final txns = [
      utang(10000, DateTime(2026, 1, 1)),
      utang(20000, DateTime(2026, 1, 5)),
      bayar(5000, DateTime(2026, 1, 6)),
    ];
    expect(computeBalance(txns), 25000);
  });

  test('jatuh tempo dihitung dengan alokasi bayar ke utang terlama', () {
    final txns = [
      utang(10000, DateTime(2026, 1, 1), due: DateTime(2026, 1, 10)),
      utang(20000, DateTime(2026, 1, 5), due: DateTime(2026, 1, 20)),
      bayar(10000, DateTime(2026, 1, 6)),
    ];
    // Utang pertama sudah lunas, tinggal yang tempo 20 Jan.
    expect(nextDueDate(txns), DateTime(2026, 1, 20));
  });

  test('tanpa tempo atau sudah lunas -> tidak ada jatuh tempo', () {
    expect(nextDueDate([utang(1000, DateTime(2026, 1, 1))]), isNull);
    expect(
      nextDueDate([
        utang(1000, DateTime(2026, 1, 1), due: DateTime(2026, 1, 10)),
        bayar(1000, DateTime(2026, 1, 2)),
      ]),
      isNull,
    );
  });

  test('status pelanggan', () {
    final c = Customer(id: 1, name: 'Bu Ani', createdAt: DateTime(2026, 1, 1));
    final now = DateTime(2026, 11, 13, 9);

    CustomerSummary s(int balance, DateTime? due) =>
        CustomerSummary(customer: c, balance: balance, nextDue: due);

    expect(s(0, null).status(now), DebtStatus.lunas);
    expect(s(5000, null).status(now), DebtStatus.lancar);
    expect(s(5000, DateTime(2026, 11, 12)).status(now), DebtStatus.telat);
    expect(s(5000, DateTime(2026, 11, 13)).status(now), DebtStatus.mendekati);
    expect(s(5000, DateTime(2026, 11, 16)).status(now), DebtStatus.mendekati);
    expect(s(5000, DateTime(2026, 11, 20)).status(now), DebtStatus.lancar);
    expect(statusText(s(5000, DateTime(2026, 11, 10)), now), 'Telat 3 hari');
  });

  test('pesan tagih memuat nama dan nominal', () {
    final msg = buildReminder(
      name: 'Pak Budi',
      balance: 45000,
      due: DateTime(2026, 11, 20),
      txns: [utang(45000, DateTime(2026, 11, 1))],
    );
    expect(msg, contains('Pak Budi'));
    expect(msg, contains('Rp 45.000'));
    expect(msg, contains('20 Nov 2026'));
  });


  test('pembayaran berlebih menghasilkan saldo piutang', () {
    final txns = [
      utang(100000, DateTime(2026, 1, 1)),
      bayar(150000, DateTime(2026, 1, 2)),
    ];

    expect(computeBalance(txns), -50000);

    final customer = Customer(
      id: 1,
      name: 'Bu Ani',
      createdAt: DateTime(2026, 1, 1),
    );

    final summary = CustomerSummary(
      customer: customer,
      balance: computeBalance(txns),
    );

    expect(summary.status(), DebtStatus.piutang);
  });

  test('kredit lama mengurangi utang baru', () {
    final txns = [
      utang(100000, DateTime(2026, 1, 1)),
      bayar(150000, DateTime(2026, 1, 2)),
      utang(70000, DateTime(2026, 1, 3),
          due: DateTime(2026, 1, 20)),
    ];

    expect(computeBalance(txns), 20000);
    expect(nextDueDate(txns), DateTime(2026, 1, 20));
  });

  test('saldo negatif tidak dianggap siklus lunas', () {
    final txns = [
      utang(100000, DateTime(2026, 1, 1)),
      bayar(150000, DateTime(2026, 1, 2)),
    ];

    expect(activeDebtCycle(txns), hasLength(2));
    expect(latestClosedDebtCycle(txns), isEmpty);
  });

  test('siklus ditutup ketika saldo kembali tepat nol', () {
    final txns = [
      utang(100000, DateTime(2026, 1, 1)),
      bayar(150000, DateTime(2026, 1, 2)),
      utang(70000, DateTime(2026, 1, 3)),
      bayar(20000, DateTime(2026, 1, 4)),
    ];

    expect(computeBalance(txns), 0);
    expect(activeDebtCycle(txns), isEmpty);
    expect(latestClosedDebtCycle(txns), hasLength(4));
  });

  test('waUri menyandikan teks', () {
    final uri = waUri('08123456789', 'Halo dunia');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/628123456789');
    expect(uri.queryParameters['text'], 'Halo dunia');
  });
}
