import 'package:flutter/material.dart';
import 'package:wild_atlantic_hub/models/booking_event.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';
import 'package:wild_atlantic_hub/utils/form_label_mapper.dart';
import 'package:intl/intl.dart';

class BookingCalendarPage extends StatefulWidget {
  const BookingCalendarPage({super.key});

  @override
  State<BookingCalendarPage> createState() => _BookingCalendarPageState();
}

class _BookingCalendarPageState extends State<BookingCalendarPage>
    with SingleTickerProviderStateMixin {
  List<BookingCalendar> _calendars = [];
  bool _isLoading = true;
  String? _errorMessage;
  late DateTime _currentMonth;
  int _selectedCalendarIndex = 0;

  // Filter state
  String _selectedFilter = 'all'; // all, active, upcoming, blocked

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    _fetchCalendars();
  }

  Future<void> _fetchCalendars() async {
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

  BookingCalendar? get _activeCalendar {
    if (_calendars.isEmpty) return null;
    if (_selectedCalendarIndex >= _calendars.length) return _calendars.first;
    return _calendars[_selectedCalendarIndex];
  }

  List<BookingEvent> get _filteredEvents {
    final cal = _activeCalendar;
    if (cal == null) return [];

    switch (_selectedFilter) {
      case 'active':
        return cal.events.where((e) => e.isActive).toList();
      case 'upcoming':
        return cal.events.where((e) => e.isUpcoming && !e.isBlocked).toList();
      case 'blocked':
        return cal.events.where((e) => e.isBlocked).toList();
      default:
        return cal.events;
    }
  }

  List<BookingEvent> _eventsForDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return _filteredEvents.where((event) {
      final start = DateTime(
        event.start.year,
        event.start.month,
        event.start.day,
      );
      final end = DateTime(event.end.year, event.end.month, event.end.day);
      return d.compareTo(start) >= 0 && d.compareTo(end) <= 0;
    }).toList();
  }

  Color _parseColor(String hex) {
    try {
      hex = hex.replaceFirst('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return const Color(0xFF333333);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Bookings', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF8CB2A4),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchCalendars,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _fetchCalendars,
              child: _calendars.isEmpty ? _buildEmptyState() : _buildBody(),
            ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchCalendars,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8CB2A4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No calendars found',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              // Calendar selector tabs
              if (_calendars.length > 1) _buildCalendarSelector(),

              if (_activeCalendar != null) ...[
                if (_calendars.length > 1)
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                // Summary card for the currently selected property
                _buildPropertyStatsCard(_activeCalendar!),
              ],
            ],
          ),
        ),

        // Calendar grid
        _buildCalendarGrid(),
        const SizedBox(height: 20),

        // Room legend
        _buildRoomLegend(),
        const SizedBox(height: 16),

        // Events list
        _buildEventsList(),
        const SizedBox(height: 20),
      ],
    );
  }

  // ─── Calendar selector ──────────────────────────────────────────

  Widget _buildCalendarSelector() {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: _calendars.asMap().entries.map((entry) {
          final idx = entry.key;
          final cal = entry.value;
          final isSelected = idx == _selectedCalendarIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedCalendarIndex = idx),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF8CB2A4)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  cal.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.grey[600],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Summary card (active property only) ───────────────────────────────

  Widget _buildPropertyStatsCard(BookingCalendar cal) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Total: non-blocked bookings whose end date is strictly after today
    // (excludes guests checking out today — they're already leaving)
    final totalThisYear = cal.events
        .where((e) => !e.isBlocked && e.end.isAfter(today))
        .length;

    // Upcoming bookings (non-blocked, check-in after today)
    final upcomingCount = cal.events
        .where((e) => !e.isBlocked && e.start.isAfter(today))
        .length;

    // Active: currently checked in (today within booking range, non-blocked)
    final activeCount = cal.events
        .where((e) => e.isActive && !e.isBlocked)
        .length;

    // Blocked slots
    final blockedCount = cal.events.where((e) => e.isBlocked).length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        children: [
          _propertyStat(
            label: 'Total',
            value: '$totalThisYear',
            icon: Icons.event_note,
            color: const Color(0xFF6C63FF),
          ),
          _statDivider(),
          _propertyStat(
            label: 'Upcoming',
            value: '$upcomingCount',
            icon: Icons.upcoming_outlined,
            color: const Color(0xFFFF8F00),
          ),
          _statDivider(),
          _propertyStat(
            label: 'Active',
            value: '$activeCount',
            icon: Icons.meeting_room_outlined,
            color: const Color(0xFF00C853),
          ),
          _statDivider(),
          _propertyStat(
            label: 'Blocked',
            value: '$blockedCount',
            icon: Icons.block,
            color: const Color(0xFF78909C),
          ),
        ],
      ),
    );
  }

  Widget _propertyStat({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(width: 1, height: 44, color: Colors.grey[200]);
  }

  // ─── Calendar grid ──────────────────────────────────────────────

  Widget _buildCalendarGrid() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final firstWeekday = DateTime(year, month, 1).weekday; // Mon=1 .. Sun=7
    final monthLabel = DateFormat('MMMM yyyy').format(_currentMonth);

    final events = List<BookingEvent>.from(_filteredEvents);
    events.sort((a, b) {
      final startCmp = a.start.compareTo(b.start);
      if (startCmp != 0) return startCmp;
      return b.end.difference(b.start).compareTo(a.end.difference(a.start));
    });

    final Map<BookingEvent, int> eventSlots = {};
    final slotEndTimes = <DateTime>[];

    for (final event in events) {
      final eventStart = DateTime(
        event.start.year,
        event.start.month,
        event.start.day,
      );
      final eventEnd = DateTime(event.end.year, event.end.month, event.end.day);

      int assignedSlot = -1;
      for (int i = 0; i < slotEndTimes.length; i++) {
        if (eventStart.isAfter(slotEndTimes[i])) {
          assignedSlot = i;
          slotEndTimes[i] = eventEnd;
          break;
        }
      }

      if (assignedSlot == -1) {
        assignedSlot = slotEndTimes.length;
        slotEndTimes.add(eventEnd);
      }
      eventSlots[event] = assignedSlot;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with month navigation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() {
                    _currentMonth = DateTime(year, month - 1, 1);
                  }),
                ),
                Text(
                  monthLabel,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() {
                    _currentMonth = DateTime(year, month + 1, 1);
                  }),
                ),
              ],
            ),
          ),

          // Day-of-week headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 4),

          // Day cells
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: _buildDayGrid(
              daysInMonth,
              firstWeekday,
              year,
              month,
              eventSlots,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayGrid(
    int daysInMonth,
    int firstWeekday,
    int year,
    int month,
    Map<BookingEvent, int> eventSlots,
  ) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final rows = <Widget>[];
    int dayCounter = 1;

    for (int week = 0; week < 6; week++) {
      if (dayCounter > daysInMonth) break;

      final weekDates = <DateTime?>[];
      for (int dow = 1; dow <= 7; dow++) {
        if ((week == 0 && dow < firstWeekday) || dayCounter > daysInMonth) {
          weekDates.add(null);
        } else {
          weekDates.add(DateTime(year, month, dayCounter));
          dayCounter++;
        }
      }

      int maxWeekSlot = -1;
      final Set<BookingEvent> weekActiveEvents = {};
      for (final date in weekDates) {
        if (date != null) {
          final events = _eventsForDate(date);
          weekActiveEvents.addAll(events);
          for (final e in events) {
            final slot = eventSlots[e] ?? 0;
            if (slot > maxWeekSlot) maxWeekSlot = slot;
          }
        }
      }

      final double rowMinHeight = 80.0;
      final double requiredHeight = 28.0 + (maxWeekSlot + 1) * 18.0 + 8.0;
      final double finalHeight = requiredHeight > rowMinHeight
          ? requiredHeight
          : rowMinHeight;

      final cells = <Widget>[];
      for (int dow = 1; dow <= 7; dow++) {
        final date = weekDates[dow - 1];
        if (date == null) {
          cells.add(
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          );
        } else {
          final isToday = date == todayDate;
          cells.add(
            Expanded(
              child: GestureDetector(
                onTap: _eventsForDate(date).isNotEmpty
                    ? () => _showDayEventsSheet(date, _eventsForDate(date))
                    : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: isToday
                        ? const Color(0xFF8CB2A4).withValues(alpha: 0.15)
                        : Colors.white,
                    border: Border.all(
                      color: isToday
                          ? const Color(0xFF8CB2A4)
                          : Colors.grey.withValues(alpha: 0.2),
                      width: isToday ? 1.5 : 0.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isToday
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: isToday
                                ? const Color(0xFF8CB2A4)
                                : Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      }

      rows.add(
        SizedBox(
          height: finalHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final colWidth = constraints.maxWidth / 7;
              final eventWidgets = <Widget>[];

              for (final e in weekActiveEvents) {
                final slot = eventSlots[e] ?? 0;
                int startCol = -1;
                int endCol = -1;
                final eventStart = DateTime(
                  e.start.year,
                  e.start.month,
                  e.start.day,
                );
                final eventEnd = DateTime(e.end.year, e.end.month, e.end.day);

                for (int i = 0; i < 7; i++) {
                  final d = weekDates[i];
                  if (d != null) {
                    if (d.compareTo(eventStart) >= 0 &&
                        d.compareTo(eventEnd) <= 0) {
                      if (startCol == -1) startCol = i;
                      endCol = i;
                    }
                  }
                }

                if (startCol != -1) {
                  final span = endCol - startCol + 1;
                  final bool isActualStart = weekDates[startCol] == eventStart;
                  final bool isActualEnd = weekDates[endCol] == eventEnd;

                  final leftOffset =
                      startCol * colWidth +
                      (isActualStart ? colWidth / 2.0 : 0.0);
                  // Subtract half column width if it starts this week, and subtract half if it ends this week
                  final width =
                      span * colWidth -
                      (isActualStart ? colWidth / 2.0 : 0.0) -
                      (isActualEnd ? colWidth / 2.0 : 0.0);

                  final topOffset = 26.0 + slot * 18.0;

                  final bgColor = _parseColor(e.backgroundColor);
                  final textColor = bgColor.computeLuminance() > 0.35
                      ? Colors.black87
                      : Colors.white;

                  String prefix = '';
                  if (e.isBlocked) {
                    prefix = '🚫 ';
                  } else {
                    final lowerRoom = e.room.toLowerCase();
                    if (lowerRoom.contains('airbnb')) {
                      prefix = '✈️ ';
                    } else if (lowerRoom.contains('booking')) {
                      prefix = '🏨 ';
                    }
                  }

                  eventWidgets.add(
                    Positioned(
                      left: leftOffset,
                      top: topOffset,
                      width: width,
                      height: 16,
                      child: GestureDetector(
                        onTap: () => _showEventDetail(e),
                        child: Container(
                          margin: EdgeInsets.only(
                            left: isActualStart ? 2.0 : 0.0,
                            right: isActualEnd ? 2.0 : 0.0,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: isActualStart ? 4.0 : 2.0,
                            vertical: 1.0,
                          ),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.horizontal(
                              left: isActualStart
                                  ? const Radius.circular(4)
                                  : Radius.zero,
                              right: isActualEnd
                                  ? const Radius.circular(4)
                                  : Radius.zero,
                            ),
                          ),
                          child: Text(
                            '$prefix${e.room.replaceFirst('Airbnb ', '').replaceFirst('Booking ', '')}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ),
                    ),
                  );
                }
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: cells,
                  ),
                  ...eventWidgets,
                ],
              );
            },
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  // ─── Room legend ──────────────────────────────────────────────

  Widget _buildRoomLegend() {
    final cal = _activeCalendar;
    if (cal == null || cal.rooms.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rooms',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: cal.rooms.map((room) {
              final color = _parseColor(room.color);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    room.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            'Solid = ✈️ Airbnb  •  Light = 🏨 Booking.com  •  Grey = 🚫 Blocked',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  // ─── Events list ──────────────────────────────────────────────

  Widget _buildEventsList() {
    final events = List<BookingEvent>.from(_filteredEvents);
    events.sort((a, b) => a.start.compareTo(b.start));

    // Show only current + future events
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final relevantEvents = events.where((e) {
      final endDate = DateTime(e.end.year, e.end.month, e.end.day);
      return endDate.isAfter(today);
    }).toList();

    if (relevantEvents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            _selectedFilter == 'all'
                ? 'No upcoming bookings'
                : 'No bookings match this filter',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ),
      );
    }

    // Checking in today: start date is exactly today
    final todayCheckIns = relevantEvents.where((e) {
      final startDate = DateTime(e.start.year, e.start.month, e.start.day);
      return startDate.isAtSameMomentAs(today);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (todayCheckIns.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8CB2A4), Color(0xFF6D9B8C)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.today, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Checking In Today',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${todayCheckIns.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...todayCheckIns.map((event) => _buildEventCard(event)),
        ],
      ],
    );
  }

  Widget _buildEventCard(BookingEvent event) {
    final bgColor = _parseColor(event.backgroundColor);
    final isBlocked = event.isBlocked;
    final dateFormatter = DateFormat('dd MMM');

    return GestureDetector(
      onTap: () => _showEventDetail(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border(left: BorderSide(color: bgColor, width: 4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Date badge
              Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: bgColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat('dd').format(event.start),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: bgColor,
                      ),
                    ),
                    Text(
                      DateFormat('MMM').format(event.start),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: bgColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.room,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _platformBadge(event.platform, isBlocked),
                        Text(
                          '${dateFormatter.format(event.start)} → ${dateFormatter.format(event.end)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    if (!isBlocked && event.formData.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: 13,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _getGuestName(event.formData),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Nights badge
              if (!isBlocked)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${event.nights}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'night${event.nights == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),

              const SizedBox(width: 2),
              Icon(Icons.chevron_right, color: Colors.grey[300], size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _platformBadge(String platform, bool isBlocked) {
    Color color;
    String label;
    if (isBlocked) {
      color = const Color(0xFF78909C);
      label = 'Blocked';
    } else if (platform == 'Airbnb') {
      color = const Color(0xFFE74C3C);
      label = '✈️ Airbnb';
    } else {
      color = const Color(0xFF2980B9);
      label = '🏨 Booking';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _getGuestName(Map<String, dynamic> formData) {
    // Try common field names for guest name
    for (final key in formData.keys) {
      final lk = key.toLowerCase();
      if (lk.contains('name') && !lk.contains('last')) {
        final val = formData[key];
        if (val != null && val.toString().isNotEmpty) return val.toString();
      }
    }
    // Fallback: try "Full Name", "Guest Name" etc.
    for (final key in formData.keys) {
      final lk = key.toLowerCase();
      if (lk.contains('name')) {
        final val = formData[key];
        if (val != null && val.toString().isNotEmpty) return val.toString();
      }
    }
    return 'Guest details available';
  }

  // ─── Day events bottom sheet ──────────────────────────────────

  void _showDayEventsSheet(DateTime date, List<BookingEvent> events) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: false,
      useSafeArea: true,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('EEEE, dd MMMM yyyy').format(date),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${events.length} booking${events.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 16),
              ...events.map((e) => _buildEventCard(e)),
            ],
          ),
        );
      },
    );
  }

  // ─── Event detail bottom sheet ────────────────────────────────

  void _showEventDetail(BookingEvent event) {
    final dateFormatter = DateFormat('dd MMM yyyy');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: false,
      useSafeArea: true,
      builder: (ctx) {
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
                        event.room,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _platformBadge(event.platform, event.isBlocked),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 20,
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
                      _detailField(
                        'Check-in',
                        dateFormatter.format(event.start),
                      ),
                      _detailField(
                        'Check-out',
                        dateFormatter.format(event.end),
                      ),
                      if (!event.isBlocked && event.nights > 0)
                        _detailField(
                          'Duration',
                          '${event.nights} night${event.nights == 1 ? '' : 's'}',
                        ),
                      if (event.isBlocked)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.block, color: Colors.grey[500]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'This slot is manually blocked and not available for booking.',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!event.isBlocked && event.formData.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Guest Details',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...event.formData.entries
                            .where((e) {
                              if (e.value == null || e.value.toString().isEmpty)
                                return false;
                              final lk = e.key.toLowerCase().replaceAll(
                                ' ',
                                '',
                              );
                              if (lk.contains('nonce') ||
                                  lk.contains('referer') ||
                                  lk.contains('token') ||
                                  lk.contains('hash') ||
                                  lk.contains('wphttp') ||
                                  (lk.contains('fluentform') &&
                                      lk.contains('nonce')) ||
                                  lk.contains('_wp_') ||
                                  lk.contains('formid') ||
                                  lk.contains('__') ||
                                  lk.startsWith('utm'))
                                return false;
                              return true;
                            })
                            .map((entry) {
                              final friendlyLabel = FormLabelMapper.getLabel(
                                entry.key,
                              );
                              final lk = friendlyLabel.toLowerCase();
                              final isSecret =
                                  lk.contains('lock') ||
                                  lk.contains('code') ||
                                  lk.contains('pin') ||
                                  lk.contains('door');
                              return _detailField(
                                friendlyLabel,
                                entry.value.toString(),
                                isSecret: isSecret,
                              );
                            }),
                      ],
                      if (!event.isBlocked && event.formData.isEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.amber[700],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No guest details found in Fluent Forms for this check-in date.',
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _detailField(String label, String value, {bool isSecret = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSecret ? '🔐 $label' : label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
