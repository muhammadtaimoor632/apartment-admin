import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';

import 'package:wild_atlantic_hub/models/booking_event.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';
import 'package:wild_atlantic_hub/models/cleaning_details.dart';
import 'package:wild_atlantic_hub/utils/form_label_mapper.dart';

class TodayCheckinsPage extends StatefulWidget {
  static final StreamController<void> refreshStream = StreamController<void>.broadcast();

  const TodayCheckinsPage({super.key});

  @override
  State<TodayCheckinsPage> createState() => _TodayCheckinsPageState();
}

class _BookingEntry {
  final String calendarName;
  final BookingEvent event;
  final BookingEvent? nextEvent;
  final bool isCompleted;
  final bool isOverdue;
  final String cleaningStatus;
  _BookingEntry({
    required this.calendarName,
    required this.event,
    this.nextEvent,
    this.isCompleted = false,
    this.isOverdue = false,
    this.cleaningStatus = 'not_cleaned',
  });
}

class _TodayCheckinsPageState extends State<TodayCheckinsPage> with WidgetsBindingObserver {
  List<BookingCalendar> _calendars = [];
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _lastFetchedDate;
  Map<String, String> _cleaningStatusesByRoomName = {};
  Timer? _refreshTimer;
  StreamSubscription? _refreshSub;
  final GlobalKey<_AdminNotepadState> _notepadKey = GlobalKey<_AdminNotepadState>();

  DateTime _lastKnownRealDate = DateTime.now();

  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  void _checkDateChange() {
    final now = DateTime.now();
    if (now.day != _lastKnownRealDate.day ||
        now.month != _lastKnownRealDate.month ||
        now.year != _lastKnownRealDate.year) {
      _lastKnownRealDate = now;
      if (mounted) {
        setState(() {
          _selectedDate = DateTime(now.year, now.month, now.day);
        });
      }
    }
  }

  String _getDateHeader() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_selectedDate.isAtSameMomentAs(today)) return 'Today';
    final tomorrow = today.add(const Duration(days: 1));
    if (_selectedDate.isAtSameMomentAs(tomorrow)) return 'Tomorrow';
    final yesterday = today.subtract(const Duration(days: 1));
    if (_selectedDate.isAtSameMomentAs(yesterday)) return 'Yesterday';

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${_selectedDate.day} ${months[_selectedDate.month - 1]}, ${_selectedDate.year}';
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: const Color(0xFF8CB2A4),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF8CB2A4),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (ApiService.lastKnownStatuses.isNotEmpty) {
      _cleaningStatusesByRoomName = Map.from(ApiService.lastKnownStatuses);
    }
    _fetchData();
    _startRefreshTimer();
    _refreshSub = TodayCheckinsPage.refreshStream.stream.listen((_) {
      if (mounted) {
        setState(() {
          if (ApiService.lastKnownStatuses.isNotEmpty) {
            _cleaningStatusesByRoomName = Map.from(ApiService.lastKnownStatuses);
          }
        });
      }
      _fetchData(silent: true);
      _notepadKey.currentState?.fetchNotes();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _refreshSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDateChange();
      if (mounted) {
        setState(() {
          if (ApiService.lastKnownStatuses.isNotEmpty) {
            _cleaningStatusesByRoomName = Map.from(ApiService.lastKnownStatuses);
          }
        });
      }
      _fetchData(silent: false);
      _notepadKey.currentState?.fetchNotes();
    }
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkDateChange();
      _fetchData(silent: true);
      _notepadKey.currentState?.fetchNotes();
    });
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

  Future<void> _fetchData({bool silent = false}) async {
    if (!mounted) return;
    
    // Only show loading if it's not a silent refresh, or if we have no data yet
    if (!silent || _calendars.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

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
        statusMap[d.name] = statuses[d.id]?.toString() ?? 'not_cleaned';
      }

      if (mounted) {
        setState(() {
          _calendars = calendars;
          _cleaningStatusesByRoomName = statusMap;
          if (!silent || _isLoading) _isLoading = false;
          _errorMessage = null;
          _lastFetchedDate = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // If silent fails, we just keep old data and don't show an explicit error overlay
          if (!silent || _calendars.isEmpty) {
            _errorMessage = 'Failed to load bookings. Pull to refresh.';
            _isLoading = false;
          }
        });
      }
    }
  }

  String _checkStatusOrDft(String key) {
    for (final entry in _cleaningStatusesByRoomName.entries) {
      if (entry.key.toLowerCase().trim() == key.toLowerCase().trim()) {
        return entry.value;
      }
    }
    return 'not_cleaned';
  }

  String _getCleaningStatus(String bookingRoom) {
    if (_cleaningStatusesByRoomName.isEmpty) return 'not_cleaned';

    final bk = bookingRoom.toLowerCase().trim();
    
    // Explicit mappings requested by user
    if (bk == 'room 1') return _checkStatusOrDft('Room 1 Eyre Square');
    if (bk == 'room 2') return _checkStatusOrDft('Room 2 Eyre Square');
    if (bk == 'room 3') return _checkStatusOrDft('Room 3 Eyre Square');
    if (bk == 'room 4') return _checkStatusOrDft('Room 4 Eyre Square');
    if (bk == 'room 5') return _checkStatusOrDft('Room 5 Eyre Square');
    if (bk == '18 kirwans court') return _checkStatusOrDft('Kirwans lane');

    for (final entry in _cleaningStatusesByRoomName.entries) {
      if (bk == entry.key.toLowerCase().trim()) return entry.value;
    }

    final bkNorm = bk.replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (bkNorm.isEmpty) return 'not_cleaned';

    for (final entry in _cleaningStatusesByRoomName.entries) {
      final clNorm = entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clNorm.isEmpty) continue;

      final regexBK = RegExp(r'\b' + RegExp.escape(bkNorm) + r'\b');
      if (regexBK.hasMatch(clNorm)) {
        return entry.value;
      }
      
      final regexCL = RegExp(r'\b' + RegExp.escape(clNorm) + r'\b');
      if (regexCL.hasMatch(bkNorm)) {
        return entry.value;
      }
    }
    
    return 'not_cleaned';
  }

  List<_BookingEntry> get _checkinsToday {
    final targetDate = _selectedDate;
    final entries = <_BookingEntry>[];
    for (final cal in _calendars) {
      for (final event in cal.events) {
        if (event.isBlocked) continue;
        final start = DateTime(
          event.start.year,
          event.start.month,
          event.start.day,
        );
        if (start.isAtSameMomentAs(targetDate)) {
          entries.add(_BookingEntry(calendarName: cal.name, event: event));
        }
      }
    }
    return entries;
  }

  List<_BookingEntry> get _currentlyHosting {
    final targetDate = _selectedDate;
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
        if (start.isBefore(targetDate) && end.isAfter(targetDate)) {
          entries.add(_BookingEntry(calendarName: cal.name, event: event));
        }
      }
    }
    return entries;
  }

  List<_BookingEntry> get _roomsToClean {
    final targetDate = _selectedDate;
    final entries = <_BookingEntry>[];

    for (final cal in _calendars) {
      final Map<String, List<BookingEvent>> byRoom = {};
      for (final e in cal.events) {
        if (!e.isBlocked) {
          byRoom.putIfAbsent(e.room, () => []).add(e);
        }
      }

      for (final roomName in byRoom.keys) {
        final status = _getCleaningStatus(roomName);
        final isCleaned = status.toLowerCase() == 'cleaned';

        final roomEvents = byRoom[roomName]!;
        final sortedEvents = List.of(roomEvents)..sort((a, b) => a.start.compareTo(b.start));

        bool isStrictlyOccupied = false;
        for (final e in sortedEvents) {
          final start = DateTime(e.start.year, e.start.month, e.start.day);
          final end = DateTime(e.end.year, e.end.month, e.end.day);
          if (targetDate.isAfter(start) && targetDate.isBefore(end)) {
            isStrictlyOccupied = true;
            break;
          }
        }

        if (isStrictlyOccupied) continue; 

        BookingEvent? lastCheckoutEvent;
        for (final e in sortedEvents) {
          final end = DateTime(e.end.year, e.end.month, e.end.day);
          if (end.isBefore(targetDate) || end.isAtSameMomentAs(targetDate)) {
            if (lastCheckoutEvent == null || end.isAfter(DateTime(lastCheckoutEvent.end.year, lastCheckoutEvent.end.month, lastCheckoutEvent.end.day))) {
               lastCheckoutEvent = e;
            }
          }
        }

        final upcoming = sortedEvents.where((e) {
          final startDate = DateTime(e.start.year, e.start.month, e.start.day);
          return startDate.isAfter(targetDate) || (startDate.isAtSameMomentAs(targetDate) && e != lastCheckoutEvent);
        }).toList();

        final nextEvent = upcoming.isNotEmpty ? upcoming.first : null;

        if (lastCheckoutEvent != null || nextEvent != null) {
          bool effectiveIsCleaned = isCleaned;
          final todayReal = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          bool isOverdue = false;

          if (lastCheckoutEvent != null) {
            final checkoutDate = DateTime(lastCheckoutEvent.end.year, lastCheckoutEvent.end.month, lastCheckoutEvent.end.day);
            
            if (checkoutDate.isAfter(todayReal)) {
               effectiveIsCleaned = false;
            }
            
            isOverdue = !effectiveIsCleaned && checkoutDate.isBefore(targetDate);
          } else if (nextEvent != null) {
            // We have a check-in coming, but the previous check-out is purged from calendar.
            // We default to not overdue, but displaying it normally.
            isOverdue = false;
          }
          
          final eventToUse = lastCheckoutEvent ?? nextEvent!;
          
          entries.add(
            _BookingEntry(
              calendarName: cal.name,
              event: eventToUse,
              nextEvent: nextEvent,
              isCompleted: effectiveIsCleaned,
              isOverdue: isOverdue,
              cleaningStatus: status,
            ),
          );
        }
      }
    }
    return entries;
  }


  String _formatTo24Hour(String timeString) {
    try {
      final normalized = timeString.trim().toUpperCase();
      final regex = RegExp(r'^(\d{1,2})(?:[:.](\d{2}))?\s*(AM|PM)?$');
      final match = regex.firstMatch(normalized);
      if (match != null) {
        int hour = int.parse(match.group(1)!);
        int minute = match.group(2) != null ? int.parse(match.group(2)!) : 0;
        String? amPm = match.group(3);

        if (amPm == 'PM' && hour < 12) hour += 12;
        if (amPm == 'AM' && hour == 12) hour = 0;

        final hourStr = hour.toString().padLeft(2, '0');
        final minStr = minute.toString().padLeft(2, '0');
        return '$hourStr:$minStr';
      }
    } catch (_) {}
    return timeString;
  }

  String? _getArrivalTime(Map<String, dynamic> formData) {
    String? foundTime;
    for (final key in formData.keys) {
      final lk = key
          .toLowerCase()
          .replaceAll(' ', '')
          .replaceAll('-', '')
          .replaceAll('_', '');
      if (lk.contains('datetime')) {
        final val = formData[key];
        if (val != null && val.toString().isNotEmpty) {
          foundTime = val.toString();
          break;
        }
      }
    }
    if (foundTime == null) {
      for (final kw in [
        'arrival time',
        'check-in time',
        'checkin time',
        'expected arrival',
      ]) {
        for (final key in formData.keys) {
          if (key.toLowerCase().contains(kw)) {
            final val = formData[key];
            if (val != null && val.toString().isNotEmpty) {
              foundTime = val.toString();
              break;
            }
          }
        }
        if (foundTime != null) break;
      }
    }
    return foundTime != null ? _formatTo24Hour(foundTime) : null;
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        leading: !isToday
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime(
                      DateTime.now().year,
                      DateTime.now().month,
                      DateTime.now().day,
                    );
                  });
                },
              )
            : null,
        title: const Text(
          'Overview',
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

    if (checkins.isEmpty &&
        hosting.isEmpty &&
        cleaning.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          _buildDateSelector(),
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
                    'All quiet on ${_getDateHeader() == "Today" ? "today" : _getDateHeader()}!',
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
        _buildDateSelector(),
        _AdminNotepad(key: _notepadKey),
        if (checkins.isNotEmpty) ...[
          _buildSectionHeader(
            '${_getDateHeader() == "Today" ? "Today's" : _getDateHeader()} Checkins',
            Icons.flight_land,
            const Color(0xFF4CAF50),
            checkins.length,
          ),
          ...checkins.map((e) => _buildCard(e, isCheckout: false)),
          const SizedBox(height: 32),
        ],
        if (hosting.isNotEmpty) ...[
          _buildSectionHeader(
            'Currently Hosting',
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
            'Cleaning',
            Icons.cleaning_services,
            const Color(0xFFFF9800),
            cleaning.length,
          ),
          ...cleaning.map((e) => _buildCard(e, isCheckout: true)),
          const SizedBox(height: 32),
        ],
      ],
    );
  }

  Widget _buildDateSelector() {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              offset: const Offset(0, 2),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8CB2A4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Color(0xFF5D8A7A),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected Date',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getDateHeader(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3E3A),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Icon(Icons.arrow_drop_down_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  String? _getSpecialRequestString(
    Map<String, dynamic>? formData, {
    String propertyName = '',
  }) {
    if (formData == null) return null;
    for (final key in formData.keys) {
      final label = FormLabelMapper.getLabel(
        key,
        propertyName: propertyName,
      ).toLowerCase();
      if (label.contains('special request') ||
          (key.toLowerCase().contains('special') &&
              key.toLowerCase().contains('request'))) {
        final value = formData[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
    }
    return null;
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
      
      final Color baseColor = entry.isOverdue ? Colors.red[600]! : Colors.orange;
      final Color bgColor = entry.isOverdue ? Colors.red[50]! : Colors.orange[50]!;
      final Color borderColor = entry.isOverdue ? Colors.red.withOpacity(0.4) : Colors.orange.withOpacity(0.2);
      final Color textColor = entry.isOverdue ? Colors.red[900]! : Colors.orange[900]!;

      if (entry.nextEvent != null) {
        final nextArrival =
            _getArrivalTime(entry.nextEvent!.formData) ?? '15:00';

        final referenceDate = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
        final nextStart = DateTime(
          entry.nextEvent!.start.year,
          entry.nextEvent!.start.month,
          entry.nextEvent!.start.day,
        );
        final diffDays = nextStart.difference(referenceDate).inDays;

        final isTodayFilter = _getDateHeader() == 'Today';
        if (diffDays <= 0) {
          subtitle = 'Check-in';
        } else if (diffDays == 1 && isTodayFilter) {
          subtitle = 'Check-in tomorrow';
        } else {
          subtitle = 'Check-in in $diffDays day${diffDays == 1 ? '' : 's'}';
        }

        timeInfo = nextArrival;
      } else {
        subtitle = entry.isOverdue ? 'Overdue Cleaning' : 'No upcoming guest found';
        timeInfo = '--';
      }

      final displaySubtitle = entry.isOverdue && entry.nextEvent != null 
          ? 'OVERDUE · $subtitle' 
          : subtitle;

      final specialReq = _getSpecialRequestString(
        entry.nextEvent?.formData,
        propertyName: entry.nextEvent?.room ?? '',
      );

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => _showEventDetail(entry, isCheckout: true),
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
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
                  border: Border.all(color: borderColor, width: entry.isOverdue ? 1.5 : 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                                displaySubtitle,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: entry.isOverdue ? Colors.red[600] : Colors.grey[600],
                                  fontWeight: entry.isOverdue ? FontWeight.w600 : FontWeight.w500,
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
                              color: bgColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 16,
                                  color: baseColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  timeInfo,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                if (specialReq != null) ...[
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Notes: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: entry.isOverdue ? Colors.red[800] : Colors.orange[800],
                          ),
                        ),
                        TextSpan(
                          text: specialReq,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isCheckout)
            Positioned(
              top: -8,
              right: -6,
              child: _buildStatusBadge(entry.cleaningStatus),
            ),
        ],
      ),
    ),
  );
} else {
  final event = entry.event;
      final arrivalTime = _getArrivalTime(event.formData) ?? '15:00';
      String displayTime;
      if (isHosting) {
        final referenceDate = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
        final endDate = DateTime(
          event.end.year,
          event.end.month,
          event.end.day,
        );
        final daysLeft = endDate.difference(referenceDate).inDays;
        if (daysLeft <= 0) {
          displayTime = 'Checkout today';
        } else if (daysLeft == 1) {
          displayTime = '1 night';
        } else {
          displayTime = '$daysLeft nights';
        }
      } else {
        displayTime = arrivalTime;
      }
      final timeIcon = isHosting ? Icons.logout : Icons.access_time;
      final specialReq = _getSpecialRequestString(
        event.formData,
        propertyName: event.room,
      );

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                    if (isHosting)
                      Text(
                        displayTime,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[500],
                        ),
                      )
                    else
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
                            Icon(
                              timeIcon,
                              size: 16,
                              color: const Color(0xFF5A8B7B),
                            ),
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
                if (specialReq != null) ...[
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Notes: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: isHosting
                                ? Colors.blue[800]
                                : const Color(0xFF4A7A6D),
                          ),
                        ),
                        TextSpan(
                          text: specialReq,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
  }
  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    String displayStatus;

    final lowerStatus = status.toLowerCase();
    if (lowerStatus == 'cleaned') {
      bgColor = Colors.green.withOpacity(0.1);
      textColor = Colors.green[700]!;
      displayStatus = 'Cleaned';
    } else if (lowerStatus == 'in_progress') {
      bgColor = Colors.blue.withOpacity(0.1);
      textColor = Colors.blue[700]!;
      displayStatus = 'In Progress';
    } else {
      bgColor = Colors.orange.withOpacity(0.1);
      textColor = Colors.orange[800]!;
      displayStatus = 'Not Cleaned';
    }

    return Text(
      displayStatus,
      style: TextStyle(
        color: textColor,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  void _showEventDetail(_BookingEntry entry, {required bool isCheckout}) {
    final formData = isCheckout
        ? entry.nextEvent?.formData
        : entry.event.formData;
    final roomName = isCheckout
        ? (entry.nextEvent?.room ?? entry.event.room)
        : entry.event.room;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
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
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // ── scrollable body ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isCheckout && entry.nextEvent == null)
                        const Text(
                          'No upcoming guests found.',
                          style: TextStyle(
                            fontSize: 15,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                        )
                      else if (formData == null || formData.isEmpty)
                        const Text(
                          "Guest hasn't filled out the form yet.",
                          style: TextStyle(fontSize: 15, color: Colors.grey),
                        )
                      else
                        ...formData.entries
                            .where((e) {
                              if (e.value == null || e.value.toString().isEmpty)
                                return false;
                              final lk = e.key.toLowerCase();
                              if (lk.contains('nonce') ||
                                  lk.contains('referer') ||
                                  lk.contains('token') ||
                                  lk.contains('hash') ||
                                  lk.contains('checkbox') ||
                                  lk.contains('wphttp'))
                                return false;
                              return true;
                            })
                            .map((e) {
                              final friendlyLabel = FormLabelMapper.getLabel(
                                e.key,
                                propertyName: roomName,
                              );
                              final lk = friendlyLabel.toLowerCase();
                              final isSecret =
                                  lk.contains('lock') ||
                                  lk.contains('code') ||
                                  lk.contains('pin') ||
                                  lk.contains('door');
                              return _labelValue(
                                isSecret ? '🔐 $friendlyLabel' : friendlyLabel,
                                e.value.toString(),
                              );
                            }),
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

  Widget _labelValue(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _AdminNotepad extends StatefulWidget {
  const _AdminNotepad({super.key});
  @override
  State<_AdminNotepad> createState() => _AdminNotepadState();
}

class _AdminNotepadState extends State<_AdminNotepad> {
  bool _loading = true;
  bool _saving = false;
  bool _isEditing = false;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchNotes();
  }

  void fetchNotes() {
    ApiService.fetchAdminNote().then((noteStr) {
      if (!mounted) return;
      if (_isEditing) return; // Do not overwrite user typing
      setState(() {
        try {
          if (noteStr.trim().startsWith('[')) {
            final List<dynamic> decoded = json.decode(noteStr);
            if (decoded.isNotEmpty) {
              // If it was the old list format, just extract all texts and join them
              _ctrl.text = decoded
                  .map((e) => e['text'].toString())
                  .where((s) => s.isNotEmpty)
                  .join('\n');
            }
          } else {
            _ctrl.text = noteStr;
          }
        } catch (_) {
          _ctrl.text = noteStr;
        }
        _loading = false;
      });
    });
  }

  Future<void> _saveNotesToServer() async {
    setState(() => _saving = true);
    final ok = await ApiService.saveAdminNote(_ctrl.text);
    if (mounted) {
      setState(() => _saving = false);
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to sync notes')));
      }
    }
  }

  void _toggleEdit() {
    if (_isEditing) {
      // Saving and exiting edit mode
      _saveNotesToServer();
    }
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    // Hide the entire block if empty and not editing?
    // Usually a notepad should always be visible so they can click edit.
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Notes',
                style: TextStyle(
                  fontSize: _isEditing ? 14 : 12, // Subtle header
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                ),
              ),
              InkWell(
                onTap: _toggleEdit,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isEditing ? Icons.check : Icons.edit,
                          size: 18,
                          color: Colors.grey[600],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_isEditing)
            TextField(
              controller: _ctrl,
              minLines: 2,
              maxLines: null,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Type your notes here...',
              ),
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            )
          else
            Text(
              _ctrl.text.isEmpty
                  ? 'Tap the pencil icon to add notes...'
                  : _ctrl.text,
              style: TextStyle(
                fontSize: 14,
                color: _ctrl.text.isEmpty ? Colors.grey[400] : Colors.black87,
                fontStyle: _ctrl.text.isEmpty
                    ? FontStyle.italic
                    : FontStyle.normal,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }
}
