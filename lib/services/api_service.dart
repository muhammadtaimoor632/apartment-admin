import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wild_atlantic_hub/models/inventory_item.dart';
import 'package:wild_atlantic_hub/models/cleaning_details.dart';
import 'package:wild_atlantic_hub/models/booking_event.dart';

class ApiService {
  static const String _wordpressUrl = 'https://wildatlanticapartments.com';
  static const String _apiNamespace = '/wp-json/apartment_admin/v1';
  static const String _username = 'info@vivantestudios.com';
  static const String _applicationPassword = 'cf6A VVaH KXqh tmMA y3hK Czhr';

  static final String _basicAuth =
      'Basic ${base64Encode(utf8.encode('$_username:$_applicationPassword'))}';

  static final Map<String, String> _authHeaders = {
    'Content-Type': 'application/json',
    'Authorization': _basicAuth,
  };
  //  Cleaning ratings reflection --

  static Future<http.Response> updateCleaningRating({
    required String apartmentId,
    required int rating,
  }) {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/ratings/update');
    return http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({
        'apartment_id': apartmentId,
        'todays_rating': rating,
      }),
    );
  }

  // --- Cleaning Status Endpoints ---

  static Future<Map<String, dynamic>> fetchCleaningStatuses() async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/status/all');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch statuses from server.');
    }
  }

  static Future<List<CleaningDetails>> fetchCleaningDetails() async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/status/details');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final List<dynamic> decodedData = json.decode(response.body);
      return decodedData.map((data) => CleaningDetails.fromJson(data)).toList();
    } else {
      throw Exception(
        'Failed to load cleaning details: ${response.reasonPhrase}',
      );
    }
  }

  static Future<http.Response> updateCleaningStatus({
    required String apartmentId,
    required String statusToSend,
    required int rating,
    int? durationMinutes,
  }) {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/status/update');
    final Map<String, dynamic> requestBody = {
      'status': statusToSend,
      'apartment_id': apartmentId,
      'todays_rating': rating,
    };
    if (durationMinutes != null) {
      requestBody['duration_minutes'] = durationMinutes;
    }

    return http.post(
      uri,
      headers: _authHeaders,
      body: json.encode(requestBody),
    );
  }

  static Future<http.Response> updateCleaningFeedback({
    required String apartmentId,
    required String remarks,
    String? base64Image,
  }) {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/status/feedback');
    return http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({
        'apartment_id': apartmentId,
        'remarks': remarks,
        if (base64Image != null) 'image': base64Image,
      }),
    );
  }

  // --- Inventory Endpoints ---

  static Future<List<InventoryItem>> fetchInventoryForApartment(String apartmentId) async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/inventory/$apartmentId');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final List<dynamic> decodedData = json.decode(response.body);
      return decodedData
          .map((item) => InventoryItem.fromJson(item, fallbackAptId: apartmentId))
          .toList();
    } else {
      throw Exception('Failed to load inventory for $apartmentId: ${response.reasonPhrase}');
    }
  }

  static Future<http.Response> updateStock(
    int itemId,
    int quantity,
  ) {
    final uri = Uri.parse(
      '$_wordpressUrl$_apiNamespace/inventory/update',
    );
    return http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({
        'id': itemId,
        'quantity': quantity,
      }),
    );
  }

  static Future<http.Response> updateImageUrl(int itemId, String imageUrl) {
    final uri = Uri.parse(
      '$_wordpressUrl$_apiNamespace/inventory/update-image',
    );
    return http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({'item_id': itemId, 'image_url': imageUrl}),
    );
  }

  static Future<InventoryItem> addItem({
    required String name,
    required String url,
    required int stock,
    required String apartmentId,
    String? base64Image,
  }) async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/inventory/add');
    final response = await http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({
        'apartment_id': apartmentId,
        'item_name': name,
        'item_image_url': base64Image ?? '', // They can parse it as a URL or a base64 string
        'image': base64Image ?? '', // Also sending 'image' matching other upload endpoints just in case
        'shop_url': url,
        'quantity': stock,
      }),
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      return InventoryItem.fromJson(json.decode(response.body));
    } else {
      final responseBody = json.decode(response.body);
      final errorMessage = responseBody['message'] ?? 'Failed to add item';
      throw Exception(errorMessage);
    }
  }

  static Future<http.Response> deleteItem(int itemId) {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/inventory/delete');
    return http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({'id': itemId}),
    );
  }

  // --- Booking Calendar Endpoints ---

  static Future<List<BookingCalendar>> fetchBookingCalendars() async {
    final uri = Uri.parse('$_wordpressUrl/wp-json/cbc/v1/calendars');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final List<dynamic> decodedData = json.decode(response.body);
      return decodedData
          .map((data) =>
              BookingCalendar.fromJson(data as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception(
          'Failed to load booking calendars: ${response.reasonPhrase}');
    }
  }

  static Future<BookingCalendar> refreshBookingCalendar(String calId) async {
    final uri = Uri.parse('$_wordpressUrl/wp-json/cbc/v1/calendars/$calId/refresh');
    final response = await http.post(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return BookingCalendar.fromJson(data as Map<String, dynamic>);
    } else {
      throw Exception(
          'Failed to refresh calendar: ${response.reasonPhrase}');
    }
  }
}
