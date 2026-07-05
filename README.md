# 🧱 Bos Depot & TB – Smart POS & Inventory System

Bos Depot & TB Smart POS adalah aplikasi **mobile berbasis Flutter** yang dirancang khusus untuk **usaha Panglong & Toko Bangunan (TB)**.  
Aplikasi ini mengintegrasikan **manajemen gudang, kasir pintar dengan negosiasi harga, manajemen hutang piutang, laporan keuangan, dashboard analitik**, serta **pencetakan nota thermal 80mm** dalam satu sistem.

---

## 🚀 Fitur Utama

### 📦 Manajemen Gudang & Produk

- Tambah, edit, dan hapus produk
- Dukungan pecahan / jumlah desimal pada stok barang
- Catat harga modal & harga jual (grosir & eceran)
- Tambah & kurangi stok
- **Histori Perubahan Stok**: Mendukung Edit & Hapus Histori Stok Parsial
- **Fitur Bagi Ongkir**: Distribusi ongkos kirim ke harga modal secara proporsional berdasarkan berat
- **Riwayat Modal Keluar (Capital History)**: Pantau total pengeluaran modal pembelian stok

---

### 🧾 Kasir Pintar (Smart POS)

- Tambah produk ke keranjang
- Dukungan **Custom Price Per Unit** di popup keranjang (dengan tombol reset)
- Edit jumlah (desimal) & harga produk secara fleksibel
- Sistem **Negosiasi Harga Otomatis**: Alert kerugian jika harga jual < harga modal, serta info potensi keuntungan
- **Fitur Potong Laba (Cut Profit)**
- Input data pelanggan terintegrasi (CRM)
- Manajemen metode pembayaran (Tunai / Transfer / QRIS / Hutang)
- Input ongkos transportasi
- Checkout transaksi & generate nota otomatis
- **Edit Transaksi**: Memungkinkan modifikasi transaksi lama secara dinamis

---

### 📖 Manajemen Hutang & Piutang (Kamar Desa)

- **Grup Hutang per Pelanggan**: Tampilan daftar hutang terstruktur per customer
- **Hitung Potensi Keuntungan pada Hutang**: Memantau laba yang tertahan
- **Shortcut Bayar Lunas**: Melunasi seluruh hutang satu pelanggan dengan satu sentuhan
- Kalkulasi sisa piutang secara otomatis dan akurat

---

### 🖨️ Nota & Sharing

- Nota otomatis format **Thermal 80mm**
- Cetak ke ESC/POS Thermal Printer
- Share nota ke **WhatsApp**
- Cetak ulang nota transaksi lama

---

### 📊 Dashboard Pintar & Laporan

- Data dashboard real-time: Omset, Keuntungan Bersih, Biaya Operasional, Pembelian Stok, Penjualan
- **Filter Bisnis (Business Filter)**: Pisahkan data analisis dan total aset antara kategori **Kayu** dan **Bangunan**
- Input fleksibel tanggal pengeluaran operasional
- Upgrade grafis UI pada layar pelaporan
- **Smart Search**: Algoritma pencarian yang lebih relevan dan akurat di semua layar
- Export laporan ke **CSV**

---

### 👥 Manajemen Pelanggan (CRM)

- Database pelanggan tersentralisasi
- Edit dan Hapus data pelanggan secara mudah

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
- Sistem mengambil Harga modal & Harga jual default
- Produk masuk ke keranjang

---

### 3️⃣ Negosiasi Harga
Saat kasir mengubah harga:
- 🔴 **Jika harga jual < harga modal**: Sistem menampilkan **alert kerugian** dan menunjukkan nominal rugi.
- 🟢 **Jika harga jual > harga modal**: Sistem menampilkan nominal keuntungan.
- Kasir dapat menggunakan fitur **Custom Price** per satuan barang.

---

### 4️⃣ Checkout & Generate Nota Otomatis
- Sistem memvalidasi data dan stok otomatis berkurang.
- Jika transaksi adalah hutang, akan otomatis masuk ke **Kamar Desa**.
- Nota dapat langsung dicetak ke Thermal Printer atau dibagikan ke WhatsApp.

---

## 🛠️ Teknologi

- Flutter & Dart
- Firebase (Cloud Firestore & Authentication)
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
Fresh Graduate Informatics Sriwijaya University 2026

---
