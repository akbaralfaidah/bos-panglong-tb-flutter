class Product {
  final int? id;
  final String name;
  final String type;        // 'KAYU' atau 'BANGUNAN'
  final String? dimensions; // Opsional: PxLxT (Ex: 400x2x3)
  final String source;      // Penanda: Supplier Agus / Stok Lama
  
  final int stock;          
  
  // HARGA MODAL
  final int buyPriceUnit;   // Modal Eceran
  final int buyPriceCubic;  // Modal Kubik / Modal Grosir
  
  // HARGA JUAL
  final int sellPriceUnit;  // Jual Eceran
  final int sellPriceCubic; // Jual Kubik / Jual Grosir

  // --- INI YANG BARU ---
  final int packContent;    // Isi per Dus (Misal: 1 Dus = 12 Pcs)

  Product({
    this.id,
    required this.name,
    required this.type,
    this.dimensions,
    this.source = '',
    required this.stock,
    required this.buyPriceUnit,
    this.buyPriceCubic = 0,
    required this.sellPriceUnit,
    this.sellPriceCubic = 0,
    this.packContent = 1, // Default 1 (kalau kayu atau barang eceran biasa)
  });

  // Konversi dari Map Database ke Object Dart
  factory Product.fromMap(Map<String, dynamic> json) => Product(
    id: json['id'],
    name: json['name'],
    type: json['type'],
    dimensions: json['dimensions'],
    source: json['source'] ?? '',
    stock: json['stock'],
    buyPriceUnit: json['buy_price_unit'],
    buyPriceCubic: json['buy_price_cubic'] ?? 0,
    sellPriceUnit: json['sell_price_unit'],
    sellPriceCubic: json['sell_price_cubic'] ?? 0,
    packContent: json['pack_content'] ?? 1, // Baca dari DB
  );

  // Konversi dari Object Dart ke Map Database
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type,
    'dimensions': dimensions,
    'source': source,
    'stock': stock,
    'buy_price_unit': buyPriceUnit,
    'buy_price_cubic': buyPriceCubic,
    'sell_price_unit': sellPriceUnit,
    'sell_price_cubic': sellPriceCubic,
    'pack_content': packContent, // Simpan ke DB
  };
  
}
class CartItemModel {
  final int productId;
  final String productName;
  final String productType; // KAYU / RENG / BANGUNAN
  final int quantity;       // Jumlah Final (Batang/Pcs) yang mengurangi stok
  final String unitType;    // Satuan Label di Struk (Ikat, Kubik, Dus, Pcs)
  final int capitalPrice;   // Modal per unit (sesuai unitType)
  final int sellPrice;      // Harga Jual per unit (sesuai unitType)
  
  CartItemModel({
    required this.productId, 
    required this.productName, 
    required this.productType,
    required this.quantity, 
    required this.unitType, 
    required this.capitalPrice, 
    required this.sellPrice
  });
}