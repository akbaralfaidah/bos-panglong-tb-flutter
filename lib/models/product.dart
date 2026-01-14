class Product {
  final int? id;
  final String name;
  final String type;        // 'KAYU' atau 'BANGUNAN'
  final String? dimensions; // Opsional: PxLxT (Ex: 400x2x3)
  final String source;      // Penanda: Supplier Agus / Stok Lama
  
  // --- PROPERTY BARU: KELAS KAYU ---
  final String? woodClass;  // Contoh: 'Kelas 1', 'Kelas 2', 'Kelas 3'

  final int stock;          
  
  // HARGA MODAL
  final int buyPriceUnit;   // Modal Eceran
  final int buyPriceCubic;  // Modal Kubik / Modal Grosir
  
  // HARGA JUAL
  final int sellPriceUnit;  // Jual Eceran
  final int sellPriceCubic; // Jual Kubik / Jual Grosir

  final int packContent;    // Isi per Dus (Misal: 1 Dus = 12 Pcs)

  Product({
    this.id,
    required this.name,
    required this.type,
    this.dimensions,
    this.source = '',
    this.woodClass, 
    required this.stock,
    required this.buyPriceUnit,
    this.buyPriceCubic = 0,
    required this.sellPriceUnit,
    this.sellPriceCubic = 0,
    this.packContent = 1, 
  });

  // Konversi dari Map Database ke Object Dart
  factory Product.fromMap(Map<String, dynamic> json) => Product(
    id: json['id'],
    name: json['name'],
    type: json['type'],
    dimensions: json['dimensions'],
    source: json['source'] ?? '',
    woodClass: json['wood_class'], 
    stock: json['stock'],
    buyPriceUnit: json['buy_price_unit'],
    buyPriceCubic: json['buy_price_cubic'] ?? 0,
    sellPriceUnit: json['sell_price_unit'],
    sellPriceCubic: json['sell_price_cubic'] ?? 0,
    packContent: json['pack_content'] ?? 1, 
  );

  // Konversi dari Object Dart ke Map Database
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type,
    'dimensions': dimensions,
    'source': source,
    'wood_class': woodClass, 
    'stock': stock,
    'buy_price_unit': buyPriceUnit,
    'buy_price_cubic': buyPriceCubic,
    'sell_price_unit': sellPriceUnit,
    'sell_price_cubic': sellPriceCubic,
    'pack_content': packContent,
  };
}

class CartItemModel {
  final int productId;
  final String productName;
  final String productType; // KAYU / RENG / BANGUNAN
  final int quantity;       // Jumlah Final (Batang/Pcs) yang mengurangi stok
  
  // FIELD PENTING: Menyimpan input asli (misal 5 Kubik) 
  // agar di history tidak berubah jadi 350 Batang
  final double requestQty;  
  
  final String unitType;    // Satuan Label di Struk (Ikat, Kubik, Dus, Pcs)
  final int capitalPrice;   // Modal per unit (sesuai unitType)
  final int sellPrice;      // Harga Jual per unit (sesuai unitType)
  
  CartItemModel({
    required this.productId, 
    required this.productName, 
    required this.productType,
    required this.quantity, 
    required this.requestQty, // Wajib diisi
    required this.unitType, 
    required this.capitalPrice, 
    required this.sellPrice
  });
}