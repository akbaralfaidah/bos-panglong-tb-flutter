import '../helpers/stock_cost_calculator.dart';

class Product {
  final int? id;
  final String name;
  final String type;        
  final String? dimensions; 
  final String source;      
  final String? woodClass;  
  final double stock;
  final double reservedStock;
  
  /// Apakah produk ini termasuk kelompok kayu (KAYU, RENG, BULAT)
  bool get isWood => StockCostCalculator.isWoodType(type);
  
  /// Stok fisik aktual di gudang (Siap Jual + Titipan/Belum Diantar)
  double get physicalStock => double.parse((stock + reservedStock).toStringAsFixed(2));

  /// Apakah stok bebas sedang defisit / diputar untuk memenuhi titipan
  bool get hasStockDeficit => stock < 0;

  /// Jumlah kekurangan stok terhadap total kewajiban titipan
  double get stockDeficit =>
      stock < 0 ? double.parse((-stock).toStringAsFixed(2)) : 0.0;

  /// Jumlah stok bebas positif yang aman dijual tanpa menyentuh titipan
  double get freeStock =>
      stock > 0 ? double.parse(stock.toStringAsFixed(2)) : 0.0;

  /// Hitung stok bebas (netto) dari target fisik aktual depot & titipan tercatat
  static double computeNetStockFromPhysical({
    required double targetPhysical,
    required double reservedStock,
  }) =>
      double.parse((targetPhysical - reservedStock).toStringAsFixed(2));

  static String _formatCleanDouble(double value) {
    final double normalized = value == 0 ? 0.0 : value;
    if (normalized == normalized.roundToDouble()) {
      return normalized.round().toString();
    }
    return normalized.toStringAsFixed(2);
  }

  /// Menampilkan stok siap jual dalam format bersih (35.75 bukan 35.749999999999)
  String get stockDisplay => _formatCleanDouble(stock);

  /// Menampilkan stok titipan (belum diantar) dalam format bersih
  String get reservedStockDisplay => _formatCleanDouble(reservedStock);

  /// Menampilkan stok fisik aktual di gudang dalam format bersih
  String get physicalStockDisplay => _formatCleanDouble(physicalStock);

  /// Menampilkan angka kekurangan stok dalam format bersih
  String get stockDeficitDisplay => _formatCleanDouble(stockDeficit);

  /// Menampilkan stok bebas positif dalam format bersih
  String get freeStockDisplay => _formatCleanDouble(freeStock);
  
  final int buyPriceUnit;   
  final int buyPriceCubic;  
  final int sellPriceUnit;  
  final int sellPriceCubic; 
  final double packContent;    
  
  int orderIndex; 
  final String? barcode; 
  final String? category; 
  
  // 🔥 TAMBAHAN KHUSUS BANGUNAN: Nyimpen nama satuan grosir (Cth: Kodi, Dus, Roll)
  final String? grosirUnit; 

  Product({
    this.id,
    required this.name,
    required this.type,
    this.dimensions,
    this.source = '',
    this.woodClass, 
    required this.stock,
    this.reservedStock = 0.0,
    required this.buyPriceUnit,
    this.buyPriceCubic = 0,
    required this.sellPriceUnit,
    this.sellPriceCubic = 0,
    this.packContent = 1.0, 
    this.orderIndex = 0,
    this.barcode, 
    this.category, 
    this.grosirUnit, // 🔥
  });

  factory Product.fromMap(Map<String, dynamic> json) => Product(
    id: json['id'],
    name: json['name'],
    type: json['type'],
    dimensions: json['dimensions'],
    source: json['source'] ?? '',
    woodClass: json['wood_class'], 
    stock: double.parse(((json['stock'] as num).toDouble()).toStringAsFixed(2)),
    reservedStock: json['reserved_stock'] != null
        ? double.parse(((json['reserved_stock'] as num).toDouble()).toStringAsFixed(2))
        : 0.0,
    buyPriceUnit: json['buy_price_unit'],
    buyPriceCubic: json['buy_price_cubic'] ?? 0,
    sellPriceUnit: json['sell_price_unit'],
    sellPriceCubic: json['sell_price_cubic'] ?? 0,
    packContent: (json['pack_content'] ?? 1).toDouble(), 
    orderIndex: json['order_index'] ?? 0,
    barcode: json['barcode'], 
    category: json['category'], 
    grosirUnit: json['grosir_unit'], // 🔥 TARIK DARI FIREBASE
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type,
    'dimensions': dimensions,
    'source': source,
    'wood_class': woodClass, 
    'stock': double.parse(stock.toStringAsFixed(2)),
    'reserved_stock': double.parse(reservedStock.toStringAsFixed(2)),
    'buy_price_unit': buyPriceUnit,
    'buy_price_cubic': buyPriceCubic,
    'sell_price_unit': sellPriceUnit,
    'sell_price_cubic': sellPriceCubic,
    'pack_content': packContent,
    'order_index': orderIndex,
    'barcode': barcode, 
    'category': category, 
    'grosir_unit': grosirUnit, // 🔥 SIMPAN KE FIREBASE
  };
}

class CartItemModel {
  final int productId;
  final String productName;
  final String productType; 
  final double quantity;       
  final double requestQty;  
  final String unitType;    
  final int capitalPrice;   
  final int sellPrice;      
  
  CartItemModel({
    required this.productId, 
    required this.productName, 
    required this.productType,
    required this.quantity, 
    required this.requestQty, 
    required this.unitType, 
    required this.capitalPrice, 
    required this.sellPrice
  });
}