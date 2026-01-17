import 'package:flutter/material.dart';
import 'universal_history_screen.dart';
import 'customer_list_screen.dart';

class DataMenuScreen extends StatelessWidget {
  const DataMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Gradient Background agar senada dengan Dashboard
    final Color bgStart = const Color(0xFF0052D4);
    final Color bgEnd = const Color(0xFF4364F7);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [bgStart, bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Menu Data Toko"),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // CARD 1: DATA TRANSAKSI LENGKAP
              _buildMenuCard(
                context,
                title: "DATA TRANSAKSI",
                subtitle: "Riwayat Penjualan, Stok, & Bensin",
                icon: Icons.history_edu,
                color: Colors.blue[800]!,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UniversalHistoryScreen())),
              ),
              
              const SizedBox(height: 20),

              // CARD 2: DATA PELANGGAN
              _buildMenuCard(
                context,
                title: "DATA PELANGGAN",
                subtitle: "Kelola Daftar Nama Pelanggan",
                icon: Icons.people_alt,
                color: Colors.purple[700]!,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, {
    required String title, 
    required String subtitle, 
    required IconData icon, 
    required Color color, 
    required VoidCallback onTap
  }) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(25),
          width: double.infinity,
          height: 140, // Tinggi Card
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 5),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 18)
            ],
          ),
        ),
      ),
    );
  }
}