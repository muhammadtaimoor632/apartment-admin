/// Model representing a single booking event from the WordPress calendar plugin.
class BookingEvent {
  final String title;
  final DateTime start;
  final DateTime end;
  final String backgroundColor;
  final String borderColor;
  final String textColor;
  final String room;
  final String platform;
  final bool isBlocked;
  final Map<String, dynamic> formData;

  BookingEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.room,
    required this.platform,
    required this.isBlocked,
    this.formData = const {},
  });

  factory BookingEvent.fromJson(Map<String, dynamic> json) {
    final props = json['extendedProps'] as Map<String, dynamic>? ?? {};
    final rawFormData = props['formData'];
    final Map<String, dynamic> parsedFormData = {};

    if (rawFormData is Map) {
      rawFormData.forEach((key, value) {
        parsedFormData[key.toString()] = value;
      });
    }

    return BookingEvent(
      title: json['title'] ?? '',
      start: DateTime.parse(json['start']),
      end: DateTime.parse(json['end']),
      backgroundColor: json['backgroundColor'] ?? '#333333',
      borderColor: json['borderColor'] ?? '#333333',
      textColor: json['textColor'] ?? '#ffffff',
      room: props['room'] ?? 'Unknown',
      platform: props['platform'] ?? 'Unknown',
      isBlocked: props['isBlocked'] == true,
      formData: parsedFormData,
    );
  }

  /// Number of nights between check-in and check-out.
  int get nights {
    return end.difference(start).inDays;
  }

  /// True if this booking is currently active (today falls within the range).
  bool get isActive {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(start) && today.isBefore(end);
  }

  /// True if this booking is in the future.
  bool get isUpcoming {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return start.isAfter(today);
  }
}

/// Represents a full calendar with its rooms and events.
class BookingCalendar {
  final String id;
  final String name;
  final List<BookingRoom> rooms;
  final List<BookingEvent> events;
  final String lastSynced;

  BookingCalendar({
    required this.id,
    required this.name,
    required this.rooms,
    required this.events,
    required this.lastSynced,
  });

  factory BookingCalendar.fromJson(Map<String, dynamic> json) {
    final roomsList = (json['rooms'] as List<dynamic>? ?? [])
        .map((r) => BookingRoom.fromJson(r as Map<String, dynamic>))
        .toList();
    final eventsList = (json['events'] as List<dynamic>? ?? [])
        .map((e) => BookingEvent.fromJson(e as Map<String, dynamic>))
        .toList();

    return BookingCalendar(
      id: json['calendar_id'] ?? '',
      name: json['calendar_name'] ?? 'Calendar',
      rooms: roomsList,
      events: eventsList,
      lastSynced: json['last_synced'] ?? '',
    );
  }
}

class BookingRoom {
  final String name;
  final String color;

  BookingRoom({required this.name, required this.color});

  factory BookingRoom.fromJson(Map<String, dynamic> json) {
    return BookingRoom(
      name: json['name'] ?? 'Unknown',
      color: json['color'] ?? '#333333',
    );
  }
}
