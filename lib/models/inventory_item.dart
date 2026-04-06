class InventoryItem {
  final int id;
  final String name;
  final String url;
  Map<String, int> stock; // Changed to a Map to hold stock for each apartment
  String imageUrl;
  final String apartmentId; // This is the 'primary' apartment for categorization

  InventoryItem({
    required this.id,
    required this.name,
    required this.url,
    required this.stock, // Now a Map
    required this.imageUrl,
    required this.apartmentId,
  });

  factory InventoryItem.fromJson(
      Map<String, dynamic> json, {String? fallbackAptId}) {
    // Safely parse the 'stock' field, handling both the old schema (map)
    // and the new backend schema (quantity)
    String aptId = json['apartment_id']?.toString() ??
        json['apartmentId']?.toString() ??
        fallbackAptId ??
        '';
    Map<String, int> stockMap = {};

    if (json['stock'] is Map) {
      json['stock'].forEach((key, value) {
        stockMap[key.toString()] = int.tryParse(value.toString()) ?? 0;
      });
    } else if (json['quantity'] != null) {
      stockMap[aptId] = int.tryParse(json['quantity'].toString()) ?? 0;
    }

    return InventoryItem(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['item_name'] ?? json['name'] ?? 'No Name',
      url: json['shop_url'] ?? json['url'] ?? '',
      stock: stockMap,
      imageUrl: json['item_image_url'] ?? json['image_url'] ?? '',
      apartmentId: aptId,
    );
  }
}
