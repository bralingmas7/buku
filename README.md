# Buku Utang Warung

Aplikasi Android untuk pemilik warung mencatat utang pelanggan. Data tersimpan di HP (SQLite), jadi jalan tanpa internet.

## Fitur (MVP)

- Daftar pelanggan diurutkan dari utang terbesar, dengan penanda warna: hijau (lancar), kuning (segera jatuh tempo, ≤ 3 hari), merah (telat), abu-abu (lunas)
- Catat utang baru cepat: tombol "Utang baru", pilih pelanggan, isi nominal, simpan
- Jatuh tempo pilihan cepat (1 minggu / 2 minggu / 1 bulan / pilih tanggal)
- Bayar sebagian atau lunas; saldo terhitung otomatis. Pembayaran dialokasikan ke utang terlama dulu (FIFO) untuk menentukan jatuh tempo
- Batas utang per pelanggan, dengan peringatan saat terlewati
- Tagih lewat WhatsApp dengan pesan sopan siap kirim (rincian terakhir ikut dilampirkan)
- Salin rekap per pelanggan sebagai teks
- Hapus catatan: tahan lama pada baris riwayat

## Struktur

```
lib/
  main.dart               entry point
  models.dart             Customer, Txn, saldo, jatuh tempo, status
  utils.dart              format rupiah/tanggal, pesan WhatsApp, rekap
  db.dart                 SQLite (sqflite)
  dialogs.dart            form pelanggan, form transaksi, pemilih pelanggan
  status_style.dart       warna status
  screens/
    home_screen.dart      daftar pelanggan + ringkasan
    customer_screen.dart  detail pelanggan + riwayat
test/utils_test.dart      unit test logika (saldo, FIFO, status, format)
.github/workflows/build-apk.yml
```

## Build di GitHub

```bash
cd buku_utang_warung
git init -b main
git add .
git commit -m "Buku utang warung: MVP"
git remote add origin https://github.com/USERNAME/buku-utang-warung.git
git push -u origin main
```

Setelah push, buka tab **Actions** → workflow **Build APK**. Kalau sudah hijau, unduh `buku-utang-warung-apk` dari bagian **Artifacts** di halaman run tersebut, ekstrak, lalu pasang `app-release.apk` di HP (izinkan "install dari sumber tidak dikenal").

Workflow ini membuat folder `android/` otomatis lewat `flutter create`, menjalankan `flutter test`, lalu `flutter build apk --release`. Kamu juga bisa menjalankannya manual lewat tombol **Run workflow**.

## Build lokal

```bash
flutter create --platforms=android --org id.warung --project-name buku_utang_warung .
flutter pub get
flutter test
flutter run
```

(Jalankan `flutter create` di folder yang sama; file `lib/` dan `pubspec.yaml` yang sudah ada jangan ditimpa. Kalau ragu, salin dulu sebagai cadangan.)

## Catatan

- APK release ini masih ditandatangani dengan kunci debug, cukup untuk dipasang langsung. Untuk Play Store, siapkan keystore sendiri dan simpan sebagai GitHub Secrets (jangan di-commit).
- Tombol WhatsApp memakai tautan `wa.me`. Tanpa nomor tersimpan, WhatsApp akan meminta memilih kontak.

## Rencana berikutnya

1. PIN untuk membatasi hapus/ubah catatan (penjaga warung)
2. Backup ke Google Drive
3. Konfirmasi pelanggan lewat tautan, sinkronisasi cloud
4. Skor kelancaran bayar per pelanggan, ekspor rekap sebagai gambar/PDF
