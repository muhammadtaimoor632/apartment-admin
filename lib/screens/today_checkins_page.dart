import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wild_atlantic_hub/models/booking_event.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';

class TodayCheckinsPage extends StatefulWidget {
  const TodayCheckinsPage({super.key});

  @override
  State<TodayCheckinsPage> createState() => _TodayCheckinsPageState();
}

class _BookingEntry {
  final String calendarName;
  final BookingEvent event;
  final BookingEvent? nextEvent;
  _BookingEntry({required this.calendarName, required this.event, this.nextEvent});
}

class _TodayCheckinsPageState extends State<TodayCheckinsPage> {
  List<BookingCalendar> _calendars = [];
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _lastFetchedDate;

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
      final calendars = await ApiService.fetchBookingCalendars();
      if (mounted) {
        setState(() {
          _calendars = calendars;
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
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final entries = <_BookingEntry>[];
    for (final cal in _calendars) {
      for (final event in cal.events) {
        if (event.isBlocked) continue;
        final start = DateTime(event.start.year, event.start.month, event.start.day);
        if (start.isAtSameMomentAs(today)) {
          entries.add(_BookingEntry(calendarName: cal.name, event: event));
        }
      }
    }
    return entries;
  }

  List<_BookingEntry> get _currentlyHosting {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final entries = <_BookingEntry>[];
    for (final cal in _calendars) {
      for (final event in cal.events) {
        if (event.isBlocked) continue;
        final start = DateTime(event.start.year, event.start.month, event.start.day);
        final end = DateTime(event.end.year, event.end.month, event.end.day);
        if (start.isBefore(today) && end.isAfter(today)) {
          entries.add(_BookingEntry(calendarName: cal.name, event: event));
        }
      }
    }
    return entries;
  }

  List<_BookingEntry> get _roomsToClean {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final entries = <_BookingEntry>[];
    
    for (final cal in _calendars) {
      final Map<String, List<BookingEvent>> byRoom = {};
      for (final e in cal.events) {
        if (!e.isBlocked) {
          byRoom.putIfAbsent(e.room, () => []).add(e);
        }
      }

      for (final roomName in byRoom.keys) {
        final roomEvents = byRoom[roomName]!;
        for (final event in roomEvents) {
          final end = DateTime(event.end.year, event.end.month, event.end.day);
          if (end.isAtSameMomentAs(today)) {
            final upcoming = roomEvents.where((e) {
              final startDate = DateTime(e.start.year, e.start.month, e.start.day);
              // It's the next booking if it starts today or in the future
              return startDate.isAfter(today) || (startDate.isAtSameMomentAs(today) && e != event);
            }).toList()..sort((a, b) => a.start.compareTo(b.start));

            final nextEvent = upcoming.isNotEmpty ? upcoming.first : null;
            entries.add(_BookingEntry(calendarName: cal.name, event: event, nextEvent: nextEvent));
          }
        }
      }
    }
    return entries;
  }

  String? _getArrivalTime(Map<String, dynamic> formData) {
    for (final key in formData.keys) {
      final lk = key.toLowerCase().replaceAll(' ', '').replaceAll('-', '').replaceAll('_', '');
      if (lk.contains('datetime')) {
        final val = formData[key];
        if (val != null && val.toString().isNotEmpty) return val.toString();
      }
    }
    for (final kw in ['arrival time', 'check-in time', 'checkin time', 'expected arrival']) {
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Today', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  TextButton(onPressed: _fetchData, child: const Text('Retry'))
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: _buildLists(),
            ),
    );
  }

  Widget _buildLists() {
    final checkins = _checkinsToday;
    final hosting = _currentlyHosting;
    final cleaning = _roomsToClean;

    if (checkins.isEmpty && hosting.isEmpty && cleaning.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: const Center(child: Text('No events today.')),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (checkins.isNotEmpty) ...[
          const Text('Guests checking in today', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...checkins.map((e) => _buildCard(e, isCheckout: false)),
          const SizedBox(height: 24),
        ],
        if (hosting.isNotEmpty) ...[
          const Text('Currently hosting guests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...hosting.map((e) => _buildCard(e, isCheckout: false)),
          const SizedBox(height: 24),
        ],
        if (cleaning.isNotEmpty) ...[
          const Text('Rooms cleaners need to clean', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...cleaning.map((e) => _buildCard(e, isCheckout: true)),
        ],
      ],
    );
  }

  Widget _buildCard(_BookingEntry entry, {required bool isCheckout}) {
    if (isCheckout) {
      final String subtitle;
      if (entry.nextEvent != null) {
        final nextArrival = _getArrivalTime(entry.nextEvent!.formData) ?? DateFormat('hh:mm a').format(entry.nextEvent!.start);
        final nextDate = DateFormat('dd MMM yyyy').format(entry.nextEvent!.start);
        subtitle = 'Next guest check-in: $nextDate, $nextArrival';
      } else {
        subtitle = 'No upcoming guest';
      }
      
      return InkWell(
        onTap: () => _showEventDetail(entry, isCheckout: true),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.event.room, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      );
    } else {
      final event = entry.event;
      final arrivalTime = _getArrivalTime(event.formData) ?? DateFormat('hh:mm a').format(event.start);
      final date = DateFormat('dd MMM yyyy').format(event.start);

      return InkWell(
        onTap: () => _showEventDetail(entry, isCheckout: false),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.room, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Checkin time: $date, $arrivalTime', style: const TextStyle(fontSize: 14)),
            ],
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
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(entry.event.room, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
                            child: Text('No upcoming guests found for this room.', style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey)),
                          )
                        else ...[
                          _NoteEditor(event: entry.nextEvent!),
                          const SizedBox(height: 24),
                          const Text('Next Guest Form Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          if (entry.nextEvent!.formData.isEmpty)
                            const Text("Guest hasn't filled out the form yet.", style: TextStyle(fontSize: 16, color: Colors.grey))
                          else
                            ...entry.nextEvent!.formData.entries.where((e) {
                              if (e.value == null || e.value.toString().isEmpty) return false;
                              final lk = e.key.toLowerCase();
                              if (lk.contains('nonce') || lk.contains('referer') || lk.contains('token') || lk.contains('hash') || lk.contains('wphttp')) return false;
                              return true;
                            }).map((e) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.key, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text(e.value.toString(), style: const TextStyle(fontSize: 16)),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ] else ...[
                        _NoteEditor(event: entry.event),
                        const SizedBox(height: 24),
                        const Text('Form Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        if (entry.event.formData.isEmpty)
                          const Text("Guest hasn't filled out the form yet.", style: TextStyle(fontSize: 16, color: Colors.grey))
                        else
                          ...entry.event.formData.entries.where((e) {
                            if (e.value == null || e.value.toString().isEmpty) return false;
                            final lk = e.key.toLowerCase();
                            if (lk.contains('nonce') || lk.contains('referer') || lk.contains('token') || lk.contains('hash') || lk.contains('wphttp')) return false;
                            return true;
                          }).map((e) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.key, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(e.value.toString(), style: const TextStyle(fontSize: 16)),
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
        const Text('Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            onPressed: _saving ? null : () async {
              setState(() => _saving = true);
              final ok = await ApiService.saveBookingNote(widget.event, _ctrl.text);
              if (mounted) {
                setState(() => _saving = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'Note saved!' : 'Failed to save note'))
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8CB2A4),
              foregroundColor: Colors.white,
            ),
            child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Note'),
          ),
        ),
      ],
    );
  }
}
