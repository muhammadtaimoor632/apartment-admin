import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wild_atlantic_hub/models/booking_event.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';
import 'package:wild_atlantic_hub/models/cleaning_details.dart';
import 'package:wild_atlantic_hub/utils/form_label_mapper.dart';

class TodayCheckinsPage extends StatefulWidget {
  const TodayCheckinsPage({super.key});

  @override
  State<TodayCheckinsPage> createState() => _TodayCheckinsPageState();
}

class _BookingEntry {
  final String calendarName;
  final BookingEvent event;
  final BookingEvent? nextEvent;
  _BookingEntry({
    required this.calendarName,
    required this.event,
    this.nextEvent,
  });
}

class _TodayCheckinsPageState extends State<TodayCheckinsPage> {
  List<BookingCalendar> _calendars = [];
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _lastFetchedDate;
  Map<String, String> _cleaningStatusesByRoomName = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final today = DateTime.now();
    if (_lastFetchedDate != null &&
        (today.year != _lastFetchedDate!.year ||
            today.month != _lastFetchedDate!.month ||
            today.day != _lastFetchedDate!.day)) {
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final calendarsFuture = ApiService.fetchBookingCalendars();
      final detailsFuture = ApiService.fetchCleaningDetails();
      final statusesFuture = ApiService.fetchCleaningStatuses();

      final results = await Future.wait([
        calendarsFuture,
        detailsFuture,
        statusesFuture,
      ]);
      final calendars = results[0] as List<BookingCalendar>;
      final details = results[1] as List<CleaningDetails>;
      final statuses = results[2] as Map<String, dynamic>;

      final Map<String, String> statusMap = {};
      for (final d in details) {
        final normName = d.name.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        statusMap[normName] = statuses[d.id]?.toString() ?? 'not_cleaned';
      }

      if (mounted) {
        setState(() {
          _calendars = calendars;
          _cleaningStatusesByRoomName = statusMap;
          _isLoading = false;
          _lastFetchedDate = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load bookings. Pull to refresh.';
          _isLoading = false;
        });
      }
    }
  }

  List<_BookingEntry> get _checkinsToday {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final entries = <_BookingEntry>[];
    for (final cal in _calendars) {
      for (final event in cal.events) {
        if (event.isBlocked) continue;
        final start = DateTime(
          event.start.year,
          event.start.month,
          event.start.day,
        );
        if (start.isAtSameMomentAs(today)) {
          entries.add(_BookingEntry(calendarName: cal.name, event: event));
        }
      }
    }
    return entries;
  }

  List<_BookingEntry> get _currentlyHosting {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final entries = <_BookingEntry>[];
    for (final cal in _calendars) {
      for (final event in cal.events) {
        if (event.isBlocked) continue;
        final start = DateTime(
          event.start.year,
          event.start.month,
          event.start.day,
        );
        final end = DateTime(event.end.year, event.end.month, event.end.day);
        if (start.isBefore(today) && end.isAfter(today)) {
          entries.add(_BookingEntry(calendarName: cal.name, event: event));
        }
      }
    }
    return entries;
  }

  List<_BookingEntry> get _roomsToClean {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final entries = <_BookingEntry>[];

    for (final cal in _calendars) {
      final Map<String, List<BookingEvent>> byRoom = {};
      for (final e in cal.events) {
        if (!e.isBlocked) {
          byRoom.putIfAbsent(e.room, () => []).add(e);
        }
      }

      for (final roomName in byRoom.keys) {
        final normRoomName = roomName.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        final status =
            _cleaningStatusesByRoomName[normRoomName] ?? 'not_cleaned';
        if (status == 'cleaned') continue;

        final roomEvents = byRoom[roomName]!;
        for (final event in roomEvents) {
          final end = DateTime(event.end.year, event.end.month, event.end.day);
          if (end.isAtSameMomentAs(today)) {
            final upcoming = roomEvents.where((e) {
              final startDate = DateTime(
                e.start.year,
                e.start.month,
                e.start.day,
              );
              // It's the next booking if it starts today or in the future
              return startDate.isAfter(today) ||
                  (startDate.isAtSameMomentAs(today) && e != event);
            }).toList()..sort((a, b) => a.start.compareTo(b.start));

            final nextEvent = upcoming.isNotEmpty ? upcoming.first : null;
            entries.add(
              _BookingEntry(
                calendarName: cal.name,
                event: event,
                nextEvent: nextEvent,
              ),
            );
          }
        }
      }
    }
    return entries;
  }

  List<_BookingEntry> get _readyForCheckin {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final entries = <_BookingEntry>[];

    for (final cal in _calendars) {
      final Map<String, List<BookingEvent>> byRoom = {};
      for (final e in cal.events) {
        if (!e.isBlocked) {
          byRoom.putIfAbsent(e.room, () => []).add(e);
        }
      }

      for (final roomName in byRoom.keys) {
        final normRoomName = roomName.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        final status =
            _cleaningStatusesByRoomName[normRoomName] ?? 'not_cleaned';
        if (status != 'cleaned') continue;

        final roomEvents = byRoom[roomName]!;
        for (final event in roomEvents) {
          final end = DateTime(event.end.year, event.end.month, event.end.day);
          if (end.isAtSameMomentAs(today)) {
            final upcoming = roomEvents.where((e) {
              final startDate = DateTime(
                e.start.year,
                e.start.month,
                e.start.day,
              );
              return startDate.isAfter(today) ||
                  (startDate.isAtSameMomentAs(today) && e != event);
            }).toList()..sort((a, b) => a.start.compareTo(b.start));

            final nextEvent = upcoming.isNotEmpty ? upcoming.first : null;
            entries.add(
              _BookingEntry(
                calendarName: cal.name,
                event: event,
                nextEvent: nextEvent,
              ),
            );
          }
        }
      }
    }
    return entries;
  }

  String? _getArrivalTime(Map<String, dynamic> formData) {
    for (final key in formData.keys) {
      final lk = key
          .toLowerCase()
          .replaceAll(' ', '')
          .replaceAll('-', '')
          .replaceAll('_', '');
      if (lk.contains('datetime')) {
        final val = formData[key];
        if (val != null && val.toString().isNotEmpty) return val.toString();
      }
    }
    for (final kw in [
      'arrival time',
      'check-in time',
      'checkin time',
      'expected arrival',
    ]) {
      for (final key in formData.keys) {
        if (key.toLowerCase().contains(kw)) {
          final val = formData[key];
          if (val != null && val.toString().isNotEmpty) return val.toString();
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text(
          'Today',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF8CB2A4),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_errorMessage!),
                  TextButton(onPressed: _fetchData, child: const Text('Retry')),
                ],
              ),
            )
          : RefreshIndicator(onRefresh: _fetchData, child: _buildLists()),
    );
  }

  Widget _buildLists() {
    final checkins = _checkinsToday;
    final hosting = _currentlyHosting;
    final cleaning = _roomsToClean;
    final ready = _readyForCheckin;

    if (checkins.isEmpty &&
        hosting.isEmpty &&
        cleaning.isEmpty &&
        ready.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_available,
                    size: 60,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'All quiet today!',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        if (checkins.isNotEmpty) ...[
          _buildSectionHeader(
            'Today\'s Checkin',
            Icons.flight_land,
            const Color(0xFF4CAF50),
            checkins.length,
          ),
          ...checkins.map((e) => _buildCard(e, isCheckout: false)),
          const SizedBox(height: 32),
        ],
        if (hosting.isNotEmpty) ...[
          _buildSectionHeader(
            'Currently hosting guests',
            Icons.hotel,
            const Color(0xFF2196F3),
            hosting.length,
          ),
          ...hosting.map(
            (e) => _buildCard(e, isCheckout: false, isHosting: true),
          ),
          const SizedBox(height: 32),
        ],
        if (cleaning.isNotEmpty) ...[
          _buildSectionHeader(
            'Rooms to clean',
            Icons.cleaning_services,
            const Color(0xFFFF9800),
            cleaning.length,
          ),
          ...cleaning.map((e) => _buildCard(e, isCheckout: true)),
          const SizedBox(height: 32),
        ],
        if (ready.isNotEmpty) ...[
          _buildSectionHeader(
            'Ready for guest check-in',
            Icons.check_circle_outline,
            const Color(0xFF4CAF50),
            ready.length,
          ),
          ...ready.map((e) => _buildCard(e, isCheckout: true)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    Color color,
    int count,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    _BookingEntry entry, {
    required bool isCheckout,
    bool isHosting = false,
  }) {
    if (isCheckout) {
      final String subtitle;
      final String timeInfo;
      if (entry.nextEvent != null) {
        final nextArrival =
            _getArrivalTime(entry.nextEvent!.formData) ?? '3:00 PM';

        final today = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        );
        final nextStart = DateTime(
          entry.nextEvent!.start.year,
          entry.nextEvent!.start.month,
          entry.nextEvent!.start.day,
        );
        final diffDays = nextStart.difference(today).inDays;

        if (diffDays <= 0) {
          subtitle = 'Next guest arriving today';
        } else if (diffDays == 1) {
          subtitle = 'Next guest arriving tomorrow';
        } else {
          subtitle = 'Next guest arriving in $diffDays days';
        }

        timeInfo = nextArrival;
      } else {
        subtitle = 'No upcoming guest found';
        timeInfo = '--';
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => _showEventDetail(entry, isCheckout: true),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: Colors.orange.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.event.room,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.nextEvent != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeInfo,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Colors.orange[900],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      final event = entry.event;
      final arrivalTime = _getArrivalTime(event.formData) ?? '3:00 PM';
      final displayTime = isHosting
          ? DateFormat('MMM d').format(event.end)
          : arrivalTime;
      final timeIcon = isHosting ? Icons.logout : Icons.access_time;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => _showEventDetail(entry, isCheckout: false),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    event.room,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8CB2A4).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(timeIcon, size: 16, color: const Color(0xFF5A8B7B)),
                      const SizedBox(width: 4),
                      Text(
                        displayTime,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF4A7A6D),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _showEventDetail(_BookingEntry entry, {required bool isCheckout}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.event.room,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isCheckout) ...[
                        if (entry.nextEvent == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 20.0),
                            child: Text(
                              'No upcoming guests found for this room.',
                              style: TextStyle(
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        else ...[
                          _NoteEditor(event: entry.nextEvent!),
                          const SizedBox(height: 24),
                          const Text(
                            'Next Guest Form Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (entry.nextEvent!.formData.isEmpty)
                            const Text(
                              "Guest hasn't filled out the form yet.",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            )
                          else
                            ...entry.nextEvent!.formData.entries
                                .where((e) {
                                  if (e.value == null ||
                                      e.value.toString().isEmpty)
                                    return false;
                                  final lk = e.key.toLowerCase();
                                  if (lk.contains('nonce') ||
                                      lk.contains('referer') ||
                                      lk.contains('token') ||
                                      lk.contains('hash') ||
                                      lk.contains('wphttp'))
                                    return false;
                                  return true;
                                })
                                .map((e) {
                                  final friendlyLabel =
                                      FormLabelMapper.getLabel(e.key);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          friendlyLabel,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          e.value.toString(),
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                        ],
                      ] else ...[
                        _NoteEditor(event: entry.event),
                        const SizedBox(height: 24),
                        const Text(
                          'Form Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (entry.event.formData.isEmpty)
                          const Text(
                            "Guest hasn't filled out the form yet.",
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          )
                        else
                          ...entry.event.formData.entries
                              .where((e) {
                                if (e.value == null ||
                                    e.value.toString().isEmpty)
                                  return false;
                                final lk = e.key.toLowerCase();
                                if (lk.contains('nonce') ||
                                    lk.contains('referer') ||
                                    lk.contains('token') ||
                                    lk.contains('hash') ||
                                    lk.contains('wphttp'))
                                  return false;
                                return true;
                              })
                              .map((e) {
                                final friendlyLabel = FormLabelMapper.getLabel(
                                  e.key,
                                );
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        friendlyLabel,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        e.value.toString(),
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NoteEditor extends StatefulWidget {
  final BookingEvent event;
  const _NoteEditor({required this.event});
  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  bool _loading = true;
  bool _saving = false;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    ApiService.fetchBookingNote(widget.event).then((note) {
      if (mounted) {
        setState(() {
          _ctrl.text = note;
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Notes',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter notes here...',
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    final ok = await ApiService.saveBookingNote(
                      widget.event,
                      _ctrl.text,
                    );
                    if (mounted) {
                      setState(() => _saving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? 'Note saved!' : 'Failed to save note',
                          ),
                        ),
                      );
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8CB2A4),
              foregroundColor: Colors.white,
            ),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save Note'),
          ),
        ),
      ],
    );
  }
}
