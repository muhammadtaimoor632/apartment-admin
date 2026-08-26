class GuestRequest {
  final int orderId;
  final String guestName;
  final String status;
  final String date;
  final String bedroomNumber;
  final String total;
  final List<GuestRequestItem> items;

  GuestRequest({
    required this.orderId,
    required this.guestName,
    required this.status,
    required this.date,
    required this.bedroomNumber,
    required this.total,
    required this.items,
  });

  factory GuestRequest.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<GuestRequestItem> parsedItems = itemsList
        .map((item) => GuestRequestItem.fromJson(item as Map<String, dynamic>))
        .toList();

    return GuestRequest(
      orderId: int.tryParse(json['order_id']?.toString() ?? '0') ?? 0,
      guestName: json['guest_name']?.toString() ?? 'Guest',
      status: json['status']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      bedroomNumber: json['bedroom_number']?.toString() ?? '',
      total: json['total']?.toString() ?? '0.00',
      items: parsedItems,
    );
  }
}

class GuestRequestItem {
  final String productName;
  final int quantity;
  final String total;

  GuestRequestItem({
    required this.productName,
    required this.quantity,
    required this.total,
  });

  factory GuestRequestItem.fromJson(Map<String, dynamic> json) {
    return GuestRequestItem(
      productName: json['product_name']?.toString() ?? '',
      quantity: int.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
      total: json['total']?.toString() ?? '0.00',
    );
  }
}
