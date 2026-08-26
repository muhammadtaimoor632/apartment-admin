import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wild_atlantic_hub/models/inventory_item.dart';
import 'package:wild_atlantic_hub/models/cleaning_details.dart';
<<<<<<< Updated upstream
=======
import 'package:wild_atlantic_hub/models/booking_event.dart';
import 'package:wild_atlantic_hub/models/guest_request.dart';
>>>>>>> Stashed changes

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

  // --- Inventory Endpoints ---

  static Future<List<InventoryItem>> fetchInventoryItems() async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/inventory/items');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final List<dynamic> decodedData = json.decode(response.body);
      return decodedData.map((item) => InventoryItem.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load inventory: ${response.reasonPhrase}');
    }
  }

  static Future<http.Response> updateStock(
    int itemId,
    String action,
    String apartmentId,
  ) {
    // Now requires apartmentId
    final uri = Uri.parse(
      '$_wordpressUrl$_apiNamespace/inventory/update-stock',
    );
    return http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({
        'item_id': itemId,
        'action': action,
        'apartmentId': apartmentId, // Send apartmentId in the request
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
  }) async {
    final uri = Uri.parse('$_wordpressUrl$_apiNamespace/inventory/add');
    final response = await http.post(
      uri,
      headers: _authHeaders,
      body: json.encode({
        'name': name,
        'url': url,
        // Send stock as a map for the specific apartment
        'stock': {apartmentId: stock},
        'apartmentId': apartmentId,
      }),
    );
    if (response.statusCode == 201) {
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
      body: json.encode({'item_id': itemId}),
    );
  }
<<<<<<< Updated upstream
=======

  // --- Booking Calendar Endpoints ---

  static Future<List<BookingCalendar>> fetchBookingCalendars() async {
    if (_preloadCalendarsFuture != null) {
      final future = _preloadCalendarsFuture!;
      _preloadCalendarsFuture = null;
      return future;
    }

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
    try {
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
    } on SocketException {
      return '';
    } catch (e) {
      if (e.toString().contains('SocketException')) return '';
      print('Network error fetching admin note: $e');
      return '';
    }
  }

  static Future<bool> saveAdminNote(String note) async {
    try {
      final uri = Uri.parse('$_wordpressUrl$_apiNamespace/booking-notes/save');
      final response = await http.post(
        uri,
        headers: _authHeaders,
        body: json.encode({'booking_key': 'Admin|GlobalNote', 'note': note}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Network error saving admin note: $e');
      return false;
    }
  }

  // --- Global Inventory Notes ---

  static Future<String> fetchGlobalInventoryNote() async {
    try {
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
    } on SocketException {
      return '';
    } catch (e) {
      if (e.toString().contains('SocketException')) return '';
      print('Network error fetching global inventory note: $e');
      return '';
    }
  }

  static Future<bool> saveGlobalInventoryNote(String note) async {
    try {
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
    } catch (e) {
      print('Network error saving global inventory note: $e');
      return false;
    }
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

  // --- Guest Requests ---
  
  static Future<List<GuestRequest>> fetchGuestRequests() async {
    final uri = Uri.parse('$_wordpressUrl/wp-json/fluent_dynamic/v1/guest-requests');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode == 200) {
      final List<dynamic> decodedData = json.decode(response.body);
      return decodedData.map((data) => GuestRequest.fromJson(data as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to load guest requests: ${response.reasonPhrase}');
    }
  }
>>>>>>> Stashed changes
}
