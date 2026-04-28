import 'dart:convert';
import 'package:flutter/foundation.dart';
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
      body: json.encode({'apartment_id': apartmentId, 'todays_rating': rating}),
    );
  }

  // --- Cleaning Status Endpoints ---

  static String _clientDateQuery() {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '?client_date=$year-$month-$day';
  }

  static Map<String, String> lastKnownStatuses = {};

  static Future<Map<String, dynamic>> fetchCleaningStatuses() async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/status/all${_clientDateQuery()}');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      lastKnownStatuses = data.map((k, v) => MapEntry(k, v.toString()));
      return data;
    } else {
      throw Exception('Failed to fetch statuses from server.');
    }
  }

  static Future<List<CleaningDetails>> fetchCleaningDetails() async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/status/details${_clientDateQuery()}');
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
    lastKnownStatuses[apartmentId] = statusToSend;

    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/status/update${_clientDateQuery()}');
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

  /// Retrieves the dedicated inventory listings from `/inventory-apartments`
  static Future<List<Map<String, dynamic>>> fetchInventoryApartments() async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/inventory-apartments');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final List<dynamic> decoded = json.decode(response.body);
      return decoded.cast<Map<String, dynamic>>();
    } else {
      throw Exception(
        'Failed to load inventory apartments: ${response.reasonPhrase}',
      );
    }
  }

  static Future<List<InventoryItem>> fetchInventoryForApartment(
    String apartmentId,
  ) async {
    final encodedId = Uri.encodeComponent(apartmentId);
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/inventory/$encodedId');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      // Handle debug response format (map with 'items' key)
      List<dynamic> decodedData;
      if (decoded is Map && decoded.containsKey('items')) {
        // Print debug info to console
        debugPrint('=== INVENTORY DEBUG ===');
        debugPrint('Raw param: ${decoded['debug_raw_param']}');
        debugPrint('Decoded ID: ${decoded['debug_decoded_id']}');
        debugPrint('All IDs in DB: ${decoded['debug_all_ids_in_db']}');
        debugPrint('Items count: ${(decoded['items'] as List).length}');
        debugPrint('=======================');
        decodedData = decoded['items'] as List<dynamic>;
      } else {
        decodedData = decoded as List<dynamic>;
      }
      return decodedData
          .map(
            (item) => InventoryItem.fromJson(item, fallbackAptId: apartmentId),
          )
          .toList();
    } else {
      throw Exception(
        'Failed to load inventory for $apartmentId: ${response.reasonPhrase}',
      );
    }
  }

  static Future<http.Response> updateStock(int itemId, int quantity) {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/inventory/update');
    return http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({'id': itemId, 'quantity': quantity}),
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
        'item_image_url':
            base64Image ?? '', // They can parse it as a URL or a base64 string
        'image':
            base64Image ??
            '', // Also sending 'image' matching other upload endpoints just in case
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
      final List<BookingCalendar> calendars = decodedData
          .map((data) => BookingCalendar.fromJson(data as Map<String, dynamic>))
          .toList();

      // Automatically sync/refresh all calendars to pull the latest fluent form data
      try {
        final refreshFutures = calendars.map(
          (cal) => refreshBookingCalendar(cal.id),
        );
        final refreshedCalendars = await Future.wait(refreshFutures);
        return refreshedCalendars;
      } catch (e) {
        debugPrint('Automatic calendar sync failed: $e');
        return calendars; // Fallback to the unrefreshed data
      }
    } else {
      throw Exception(
        'Failed to load booking calendars: ${response.reasonPhrase}',
      );
    }
  }

  static Future<BookingCalendar> refreshBookingCalendar(String calId) async {
    final uri = Uri.parse(
      '$_wordpressUrl/wp-json/cbc/v1/calendars/$calId/refresh',
    );
    final response = await http.post(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return BookingCalendar.fromJson(data as Map<String, dynamic>);
    } else {
      throw Exception('Failed to refresh calendar: ${response.reasonPhrase}');
    }
  }

  // --- Booking Notes Endpoints ---

  /// Returns a stable key for a booking, used as the server-side note identifier.
  static String bookingKey(BookingEvent event) {
    final date =
        '${event.start.year}-${event.start.month.toString().padLeft(2, '0')}-${event.start.day.toString().padLeft(2, '0')}';
    return '${event.room}|$date';
  }

  static Future<String> fetchBookingNote(BookingEvent event) async {
    final key = Uri.encodeComponent(bookingKey(event));
    final uri = Uri.parse(
      '$_wordpressUrl$_apiNamespace/booking-notes/get?booking_key=$key',
    );
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['note'] ?? '') as String;
    }
    return '';
  }

  static Future<bool> saveBookingNote(BookingEvent event, String note) async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/booking-notes/save');
    final response = await http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({'booking_key': bookingKey(event), 'note': note}),
    );
    return response.statusCode == 200;
  }

  // --- Admin General Notes ---

  static Future<String> fetchAdminNote() async {
    const key = 'Admin|GlobalNote';
    final uri = Uri.parse(
      '$_wordpressUrl$_apiNamespace/booking-notes/get?booking_key=$key',
    );
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['note'] ?? '') as String;
    }
    return '';
  }

  static Future<bool> saveAdminNote(String note) async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/booking-notes/save');
    final response = await http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({'booking_key': 'Admin|GlobalNote', 'note': note}),
    );
    return response.statusCode == 200;
  }

  // --- Global Inventory Notes ---

  static Future<String> fetchGlobalInventoryNote() async {
    const key = 'Admin|GlobalInventoryNote';
    final uri = Uri.parse(
      '$_wordpressUrl$_apiNamespace/booking-notes/get?booking_key=$key',
    );
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['note'] ?? '') as String;
    }
    return '';
  }

  static Future<bool> saveGlobalInventoryNote(String note) async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/booking-notes/save');
    final response = await http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({
        'booking_key': 'Admin|GlobalInventoryNote',
        'note': note,
      }),
    );
    return response.statusCode == 200;
  }

  // --- Inventory Notes ---

  static Future<String> fetchInventoryNote(String apartmentId) async {
    final key = Uri.encodeComponent('Inventory|$apartmentId');
    final uri = Uri.parse(
      '$_wordpressUrl$_apiNamespace/booking-notes/get?booking_key=$key',
    );
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['note'] ?? '') as String;
    }
    return '';
  }

  static Future<bool> saveInventoryNote(String apartmentId, String note) async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/booking-notes/save');
    final response = await http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({
        'booking_key': 'Inventory|$apartmentId',
        'note': note,
      }),
    );
    return response.statusCode == 200;
  }
}
