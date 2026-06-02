class Product {
  final int? id;
  final String name;
  final String type;        
  final String? dimensions; 
  final String source;      
  final String? woodClass;  
  final double stock;          
  
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
    stock: (json['stock'] as num).toDouble(),
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
    'stock': stock,
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