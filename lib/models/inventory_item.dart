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

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    // Safely parse the 'stock' field, which is now an object from the API
    Map<String, int> stockMap = {};
    if (json['stock'] is Map) {
      json['stock'].forEach((key, value) {
        // Ensure values are integers, default to 0 if parsing fails
        stockMap[key] = int.tryParse(value.toString()) ?? 0;
      });
    }

    return InventoryItem(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'No Name',
      url: json['url'] ?? '',
      stock: stockMap, // Assign the parsed map
      imageUrl: json['image_url'] ?? '',
      apartmentId: json['apartmentId'] ?? '',
    );
  }
}