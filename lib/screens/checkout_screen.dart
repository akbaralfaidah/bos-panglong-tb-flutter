import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../helpers/session_manager.dart'; 
import '../controllers/checkout_controller.dart';
import 'cashier_screen.dart'; 
import '../theme/app_colors.dart'; 
import 'transaction_detail_screen.dart'; // Layar Nota / Detail Transaksi

class CheckoutScreen extends StatefulWidget {
  final List<CartItem> cartItems;

  const CheckoutScreen({super.key, required this.cartItems});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController(); // INPUT BARU
  final TextEditingController _customerAddressController = TextEditingController(); // INPUT BARU
  
  final TextEditingController _bensinController = TextEditingController();
  final TextEditingController _totalFinalController = TextEditingController(); 
  
  final CheckoutController _controller = CheckoutController();
  
  List<String> _savedCustomers = [];
  bool _isLoading = false;
  String _paymentMethod = "CASH";
  String _paymentStatus = "Lunas";

  bool _isTotalManuallyEdited = false; // LOGIKA BARU AUTO-SUM

  int get _subTotal => widget.cartItems.fold(0, (sum, item) => sum + item.agreedPriceTotal);
  int get _uangBensin {
    String t = _bensinController.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(t) ?? 0;
  }
  int get _totalBayar {
    String t = _totalFinalController.text.replaceAll(RegExp(r'[^0-9]'), '');
    int manualTotal = int.tryParse(t) ?? 0;
    return manualTotal > 0 ? manualTotal : _subTotal;
  }

  @override
  void initState() {
    super.initState();
    _totalFinalController.text = _formatRpNoSymbol(_subTotal);
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final customers = await _controller.getSavedCustomers();
    if (mounted) {
      setState(() => _savedCustomers = customers);
    }
  }

void _processPayment() async {
    if (widget.cartItems.isEmpty) {
      _showSnack("Keranjang kosong!", AppColors.statusRed);
      return;
    }

    if (!SessionManager().isOwner && _paymentStatus == "Belum Lunas") {
      _showSnack("Karyawan tidak diizinkan membuat transaksi Hutang!", AppColors.statusRed);
      return;
    }

    setState(() => _isLoading = true);

    try {
      String baseName = _customerController.text.trim();
    if (baseName.isEmpty) baseName = "Pelanggan Umum";
      
      String finalCustomerInfo = baseName;
      if (_customerPhoneController.text.isNotEmpty) finalCustomerInfo += " - ${_customerPhoneController.text}";
      if (_customerAddressController.text.isNotEmpty) finalCustomerInfo += "\n${_customerAddressController.text}";

      int transId = await _controller.processTransaction(
        cartItems: widget.cartItems,
        totalPrice: _totalBayar,
        operationalCost: _uangBensin,
        customerName: finalCustomerInfo,
        paymentMethod: _paymentMethod,
        paymentStatus: _paymentStatus,
      );

      if (transId != -1) {
        if (mounted) {
          // NAVIGASI BARU: Lempar ke layar Nota dengan mode Sukses (isNewTransaction = true)
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => 
            TransactionDetailScreen(
              transaction: {
                'id': transId,
                'total_price': _totalBayar,
                'discount': _subTotal - _totalBayar > 0 ? _subTotal - _totalBayar : 0,
                'payment_status': _paymentStatus,
                'transaction_date': DateTime.now().toString(),
                'customer_name': finalCustomerInfo,
                'payment_method': _paymentMethod
              },
              isNewTransaction: true, // FLAG BARU
            )
          )); 
        }
      } else {
        _showSnack("Gagal menyimpan transaksi.", AppColors.statusRed);
      }
    } catch (e) {
      _showSnack("Terjadi kesalahan: $e", AppColors.statusRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: color));
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
  String _formatRpNoSymbol(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite, 
      appBar: AppBar(
        title: const Text("Detail Pembayaran", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- KARTU TOTAL BELANJA ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primaryNavy, 
                    borderRadius: BorderRadius.circular(20), 
                    boxShadow: [BoxShadow(color: AppColors.primaryNavy.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))]
                  ),
                  child: Column(
                    children: [
                      const Text("TOTAL BELANJA", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      const SizedBox(height: 10),
                      FittedBox(child: Text(_formatRp(_subTotal), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: AppColors.accentGold))),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // --- IDENTITAS PELANGGAN LENGKAP ---
                const Text("Data Pelanggan (Opsional)", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(height: 10),
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                    return _savedCustomers.where((String option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                  },
                  onSelected: (String selection) => _customerController.text = selection,
                  fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                    if (controller.text != _customerController.text) controller.text = _customerController.text;
                    return TextField(
                      controller: controller, focusNode: focusNode, onEditingComplete: onEditingComplete,
                      onChanged: (v) => _customerController.text = v,
                      decoration: _inputStyle("Nama Pelanggan", Icons.person),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _customerPhoneController, keyboardType: TextInputType.phone, decoration: _inputStyle("No. HP / WA", Icons.phone))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: _customerAddressController, decoration: _inputStyle("Alamat Pengiriman", Icons.location_on)),
                const SizedBox(height: 25),

                // --- METODE PEMBAYARAN ---
                const Text("Metode Pembayaran", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildRadioOption("Tunai (CASH)", "CASH", _paymentMethod, (v) => setState(() => _paymentMethod = v!), AppColors.primaryNavy)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildRadioOption("Transfer (TF)", "TRANSFER", _paymentMethod, (v) => setState(() => _paymentMethod = v!), AppColors.primaryNavy)),
                  ],
                ),
                const SizedBox(height: 25),
                
                // --- STATUS LUNAS / BON ---
                const Text("Status Pembayaran", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildRadioOption("Lunas", "Lunas", _paymentStatus, (v) => setState(() => _paymentStatus = v!), AppColors.statusGreen)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildRadioOption("Bon / Hutang", "Belum Lunas", _paymentStatus, (v) => setState(() => _paymentStatus = v!), AppColors.statusRed)),
                  ],
                ),
                
                const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(thickness: 1)),

                // --- PENYESUAIAN (BENSIN & TOTAL FINAL) ---
                const Text("Penyesuaian", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(height: 10),
                TextField(
                  controller: _bensinController, keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                  decoration: _inputStyle("Tambahan Uang Bensin", Icons.local_gas_station, prefix: "Rp "),
                  onChanged: (v) {
                    // LOGIKA BARU: Otomatis tambah ke Total Final jika belum diedit manual
                    if (!_isTotalManuallyEdited) {
                      int bensin = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                      _totalFinalController.text = _formatRpNoSymbol(_subTotal + bensin);
                    }
                  },
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _totalFinalController, keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 18),
                  decoration: _inputStyle("Total Final (Bisa Disesuaikan)", Icons.account_balance_wallet, prefix: "Rp "),
                  onChanged: (v) => _isTotalManuallyEdited = true, // Tandai kalau Karyawan nge-edit manual
                ),
                const SizedBox(height: 40),

                // --- TOMBOL SUBMIT ---
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 5,
                      shadowColor: AppColors.primaryNavy.withOpacity(0.4)
                    ),
                    onPressed: _isLoading ? null : _processPayment,
                    child: _isLoading 
                        ? const CircularProgressIndicator(color: AppColors.accentGold)
                        : const Text("YAKIN & BAYAR", style: TextStyle(color: AppColors.accentGold, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  ),
                ),
                const SizedBox(height: 50), 
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputStyle(String label, IconData icon, {String? prefix}) {
    return InputDecoration(
      labelText: label, 
      prefixText: prefix,
      prefixIcon: Icon(icon, color: AppColors.textGrey),
      filled: true, fillColor: AppColors.pureWhite,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: AppColors.primaryNavy, width: 2)),
    );
  }

  Widget _buildRadioOption(String title, String value, String groupValue, Function(String?) onChanged, Color activeColor) {
    bool isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.1) : AppColors.pureWhite,
          border: Border.all(color: isSelected ? activeColor : Colors.grey.shade300, width: isSelected ? 2 : 1),
          borderRadius: BorderRadius.circular(12)
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isSelected ? activeColor : AppColors.textGrey, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(title, style: TextStyle(color: isSelected ? activeColor : AppColors.textDark, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override 
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { 
    if(n.selection.baseOffset == 0) return n; 
    String c = n.text.replaceAll(RegExp(r'[^0-9]'), ''); 
    int v = int.tryParse(c) ?? 0; 
    String t = NumberFormat('#,###', 'id_ID').format(v); 
    return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); 
  }
}