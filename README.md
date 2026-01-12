# 🧱 Bos Panglong & TB – Smart POS & Inventory System

Bos Panglong & TB Smart POS adalah aplikasi **mobile berbasis Flutter** yang dirancang khusus untuk **usaha Panglong & Toko Bangunan (TB)**.  
Aplikasi ini mengintegrasikan **manajemen gudang, kasir pintar dengan negosiasi harga, laporan keuangan, dashboard analitik**, serta **pencetakan nota thermal 80mm** dalam satu sistem.

---

## 🚀 Fitur Utama

### 📦 Manajemen Gudang & Produk
- Tambah produk
- Edit produk
- Hapus produk
- Tambah & kurangi stok
- Catat harga modal & harga jual
- Histori perubahan stok

---

### 🧾 Kasir Pintar (Smart POS)
- Tambah produk ke keranjang
- Edit jumlah & harga produk
- Hapus produk dari keranjang
- Input data customer (nama & nomor HP)
- Metode pembayaran (Tunai / Transfer / QRIS)
- Input ongkos transportasi
- Sistem **negosiasi harga otomatis**
- Checkout & generate nota

---

### 🖨️ Nota & Sharing
- Nota otomatis format **Thermal 80mm**
- Cetak ke thermal printer
- Share nota ke **WhatsApp**
- Cetak ulang nota transaksi lama

---

### 📊 Dashboard Pintar
Menampilkan data real-time:
- 💰 Keuntungan Bersih
- 📈 Omset
- ⛽ Biaya bensin / operasional
- 📦 Total harga modal / pembelian stok
- 🛒 Jumlah produk terjual hari ini

Setiap item dashboard:
- Bisa diklik
- Menampilkan histori detail
- Bisa dicetak atau dibagikan

---

### 📑 Laporan & Export
- Laporan:
  - Harian
  - Mingguan
  - Bulanan
  - Rentang waktu tertentu
- Export laporan ke **CSV**
- Cetak laporan

---

### ☁️ Backup & Restore Data
- Backup data produk & transaksi
- Restore data saat pindah perangkat
- Menghindari kehilangan data

---

## 🔄 Flow Kasir + Negosiasi + Nota

### 1️⃣ Mulai Transaksi
- Kasir membuka menu **Kasir**
- Sistem membuat transaksi baru

---

### 2️⃣ Tambah Produk ke Keranjang
- Kasir memilih produk
- Menginput jumlah produk
- Sistem mengambil:
  - Harga modal
  - Harga jual default
- Produk masuk ke keranjang

---

### 3️⃣ Negosiasi Harga
Saat kasir mengubah harga:
- 🔴 **Jika harga jual < harga modal**
  - Sistem menampilkan **alert kerugian**
  - Menunjukkan nominal rugi
- 🟢 **Jika harga jual > harga modal**
  - Sistem menampilkan nominal keuntungan
- Kasir dapat:
  - Melanjutkan transaksi
  - Atau mengubah harga kembali

---

### 4️⃣ Kelola Keranjang
- Edit jumlah produk
- Edit harga produk
- Hapus produk dari keranjang
- Total harga dihitung otomatis

---

### 5️⃣ Input Data Customer
- Nama customer
- Nomor HP customer
- Pilih metode pembayaran
- Input ongkos transportasi (opsional)

---

### 6️⃣ Checkout Transaksi
- Sistem memvalidasi data
- Stok otomatis berkurang
- Transaksi disimpan ke database
- Data masuk laporan & dashboard

---

### 7️⃣ Generate Nota Otomatis
Nota berisi:
- Nama toko
- Tanggal & waktu transaksi
- Data customer
- Detail produk
- Subtotal
- Ongkos transportasi
- Total akhir
- Metode pembayaran

---

### 8️⃣ Output Nota
- Cetak ke **Thermal Printer 80mm**
- Share nota ke **WhatsApp**
- Simpan histori transaksi

---

### 9️⃣ Update Dashboard
- Omset bertambah
- Keuntungan bersih ter-update
- Jumlah produk terjual hari ini bertambah
- Histori transaksi dapat dilihat & dicetak

---

## 🛠️ Teknologi
- Flutter & Dart
- Local Database (SQLite / Hive)
- State Management (Provider / Riverpod / Bloc)
- ESC/POS Thermal Printer
- CSV Export
- WhatsApp Share Intent

---

## 🎯 Target Pengguna
- Panglong kayu
- Toko bangunan (TB)
- Usaha material konstruksi
- UMKM retail bahan bangunan

---

## 👨‍💻 Developer
**Akbar Alfaidah**  
FreshGraduate Informatics Sriwijaya UnIversity 2026
---