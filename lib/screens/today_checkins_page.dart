import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wild_atlantic_hub/models/booking_event.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';

class TodayCheckinsPage extends StatefulWidget {
  const TodayCheckinsPage({super.key});

  @override
  State<TodayCheckinsPage> createState() => _TodayCheckinsPageState();
}

class _TodayCheckinsPageState extends State<TodayCheckinsPage> {
  List<BookingCalendar> _calendars = [];
  bool _isLoading = true;
  String? _errorMessage;
  // Track which date was last fetched to auto-refresh daily
  DateTime? _lastFetchedDate;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-refresh if the date has changed since last fetch (daily refresh)
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

  // ─── Today's check-ins ────────────────────────────────────────────────────

  List<_CheckinEntry> get _todayCheckins {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entries = <_CheckinEntry>[];

    for (final cal in _calendars) {
      for (final event in cal.events) {
        final startDate = DateTime(
          event.start.year,
          event.start.month,
          event.start.day,
        );
        if (startDate.isAtSameMomentAs(today) && !event.isBlocked) {
          entries.add(_CheckinEntry(calendarName: cal.name, event: event));
        }
      }
    }
    return entries;
  }

  // ─── Today's checkouts + next guest ──────────────────────────────────────

  /// Returns one entry per room that checks out today,
  /// with the next upcoming booking for that same room attached.
  List<_CheckoutEntry> get _todayCheckouts {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entries = <_CheckoutEntry>[];

    for (final cal in _calendars) {
      // Group events by room name
      final Map<String, List<BookingEvent>> byRoom = {};
      for (final e in cal.events) {
        if (!e.isBlocked) {
          byRoom.putIfAbsent(e.room, () => []).add(e);
        }
      }

      for (final roomName in byRoom.keys) {
        final roomEvents = byRoom[roomName]!;
        // Find events checking out today
        for (final event in roomEvents) {
          final endDate = DateTime(
            event.end.year,
            event.end.month,
            event.end.day,
          );
          if (endDate.isAtSameMomentAs(today)) {
            // Find the next booking for this room after today
            final upcoming = roomEvents.where((e) {
              final startDate = DateTime(
                e.start.year,
                e.start.month,
                e.start.day,
              );
              return startDate.isAfter(today) ||
                  startDate.isAtSameMomentAs(today);
            }).toList()..sort((a, b) => a.start.compareTo(b.start));

            final nextBooking = upcoming.isNotEmpty ? upcoming.first : null;

            entries.add(
              _CheckoutEntry(
                calendarName: cal.name,
                checkoutEvent: event,
                nextBooking: nextBooking,
              ),
            );
          }
        }
      }
    }

    return entries;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Color _parseColor(String hex) {
    try {
      hex = hex.replaceFirst('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return const Color(0xFF333333);
    }
  }

  String _getGuestName(Map<String, dynamic> formData) {
    for (final key in formData.keys) {
      final lk = key.toLowerCase();
      if (lk.contains('name') && !lk.contains('last')) {
        final val = formData[key];
        if (val != null && val.toString().isNotEmpty) return val.toString();
      }
    }
    for (final key in formData.keys) {
      final lk = key.toLowerCase();
      if (lk.contains('name')) {
        final val = formData[key];
        if (val != null && val.toString().isNotEmpty) return val.toString();
      }
    }
    return 'Guest';
  }

  String? _getGuestField(Map<String, dynamic> formData, List<String> keywords) {
    for (final key in formData.keys) {
      final lk = key.toLowerCase();
      for (final kw in keywords) {
        if (lk.contains(kw)) {
          final val = formData[key];
          if (val != null && val.toString().isNotEmpty) return val.toString();
        }
      }
    }
    return null;
  }

  String? _getArrivalTime(Map<String, dynamic> formData) {
    // 1) The user specifies there is a 'datetime' field in the form.
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

    // 2) Look for explicit time fields
    final explicit = _getGuestField(formData, [
      'arrival time',
      'check-in time',
      'checkin time',
      'expected arrival',
      'time of arrival',
    ]);
    if (explicit != null) return explicit;

    // 3) Look for any field with 'time'
    for (final key in formData.keys) {
      final lk = key.toLowerCase();
      if ((lk.contains('arrival') ||
              lk.contains('checkin') ||
              lk.contains('check-in')) &&
          lk.contains('time')) {
        final val = formData[key];
        if (val != null && val.toString().isNotEmpty) return val.toString();
      }
    }

    return null;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Today', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF8CB2A4),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorState()
          : RefreshIndicator(onRefresh: _fetchData, child: _buildBody()),
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
              onPressed: _fetchData,
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

  Widget _buildBody() {
    final checkins = _todayCheckins;
    final checkouts = _todayCheckouts;
    final now = DateTime.now();
    final todayFormatted = DateFormat('EEEE, dd MMMM yyyy').format(now);

    final hasAnything = checkins.isNotEmpty || checkouts.isNotEmpty;

    if (!hasAnything) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8CB2A4).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.event_available,
                      size: 56,
                      color: Color(0xFF8CB2A4),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'All Quiet Today',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    todayFormatted,
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No check-ins or check-outs today.',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // ─── Summary header ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8CB2A4), Color(0xFF6D9B8C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8CB2A4).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.today, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todayFormatted,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (checkins.isNotEmpty)
                          '${checkins.length} Check-in${checkins.length == 1 ? '' : 's'}',
                        if (checkouts.isNotEmpty)
                          '${checkouts.length} Check-out${checkouts.length == 1 ? '' : 's'}',
                      ].join('  ·  '),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ─── Check-ins section ────────────────────────────────────────────
        if (checkins.isNotEmpty) ...[
          _sectionHeader(
            icon: Icons.flight_land_rounded,
            label: 'Check-ins Today',
            count: checkins.length,
            color: const Color(0xFF8CB2A4),
          ),
          const SizedBox(height: 10),
          ...checkins.map((ci) => _buildCheckinCard(ci.event)),
          const SizedBox(height: 20),
        ],

        // ─── Checkouts + Next Guest Prep section ─────────────────────────
        if (checkouts.isNotEmpty) ...[
          _sectionHeader(
            icon: Icons.flight_takeoff_rounded,
            label: 'Checkouts & Next Guest Prep',
            count: checkouts.length,
            color: const Color(0xFFE57373),
          ),
          const SizedBox(height: 6),
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tips_and_updates_outlined,
                  size: 16,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'These rooms are checking out today. The next guest\'s details are shown so cleaners can prepare accordingly.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...checkouts.map((co) => _buildCheckoutCard(co)),
        ],
      ],
    );
  }

  // ─── Section header widget ────────────────────────────────────────────────

  Widget _sectionHeader({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.grey[700],
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Check-in card ────────────────────────────────────────────────────────

  Widget _buildCheckinCard(BookingEvent event) {
    final bgColor = _parseColor(event.backgroundColor);
    final dateFormatter = DateFormat('dd MMM');
    final guestName = _getGuestName(event.formData);
    final arrivalTime = _getArrivalTime(event.formData);
    final lockCode = _getGuestField(event.formData, ['lock', 'code', 'pin']);
    final email = _getGuestField(event.formData, ['email', 'mail']);
    final phone = _getGuestField(event.formData, ['phone', 'mobile', 'tel']);

    return GestureDetector(
      onTap: () => _showEventDetail(event, isCheckin: true),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
          border: Border(left: BorderSide(color: bgColor, width: 4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _platformBadge(event.platform),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: bgColor.withValues(alpha: 0.12),
                    child: Icon(Icons.person, color: bgColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          guestName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (email != null)
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${event.nights}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'night${event.nights == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _infoChip(
                    Icons.calendar_today,
                    '${dateFormatter.format(event.start)} → ${dateFormatter.format(event.end)}',
                    Colors.blueGrey,
                  ),
                  if (arrivalTime != null)
                    _infoChip(
                      Icons.access_time,
                      arrivalTime,
                      const Color(0xFF8CB2A4),
                    ),
                  if (phone != null) _infoChip(Icons.phone, phone, Colors.blue),
                  if (lockCode != null)
                    _infoChip(Icons.lock, lockCode, const Color(0xFFC62828)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Checkout + Next Guest Prep card ─────────────────────────────────────

  Widget _buildCheckoutCard(_CheckoutEntry entry) {
    final checkoutEvent = entry.checkoutEvent;
    final nextBooking = entry.nextBooking;
    final bgColor = _parseColor(checkoutEvent.backgroundColor);
    final dateFormatter = DateFormat('dd MMM');
    final checkingOutGuest = _getGuestName(checkoutEvent.formData);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
        border: Border(
          left: BorderSide(color: const Color(0xFFE57373), width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Checkout row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
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
                            checkoutEvent.room,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 12,
                                color: const Color(0xFFE57373),
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  entry.calendarName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[600],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _platformBadge(checkoutEvent.platform),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(
                        0xFFE57373,
                      ).withValues(alpha: 0.12),
                      child: const Icon(
                        Icons.flight_takeoff_rounded,
                        color: Color(0xFFE57373),
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$checkingOutGuest is checking out',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE57373),
                            ),
                          ),
                          Text(
                            'Stayed ${checkoutEvent.nights} night${checkoutEvent.nights == 1 ? '' : 's'} · '
                            '${dateFormatter.format(checkoutEvent.start)} → ${dateFormatter.format(checkoutEvent.end)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Next Guest Prep ───────────────────────────────────────────
          if (nextBooking != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              height: 1,
              color: Colors.grey.shade100,
            ),
            GestureDetector(
              onTap: () => _showEventDetail(nextBooking, isCheckin: false),
              child: Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF8CB2A4).withValues(alpha: 0.08),
                      const Color(0xFF6D9B8C).withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF8CB2A4).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: Color(0xFF8CB2A4),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Next Guest',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF8CB2A4),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF8CB2A4,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Check-in: ${dateFormatter.format(nextBooking.start)}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF4A7A6D),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildNextGuestInfo(nextBooking),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Tap for full details',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // No next booking found
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_busy, size: 16, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Text(
                      'No upcoming booking found for this room.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNextGuestInfo(BookingEvent nextBooking) {
    final guestName = _getGuestName(nextBooking.formData);
    final arrivalTime = _getArrivalTime(nextBooking.formData);
    final lockCode = _getGuestField(nextBooking.formData, [
      'lock',
      'code',
      'pin',
    ]);
    final email = _getGuestField(nextBooking.formData, ['email', 'mail']);
    final phone = _getGuestField(nextBooking.formData, [
      'phone',
      'mobile',
      'tel',
    ]);
    final dateFormatter = DateFormat('dd MMM');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: const Color(0xFF8CB2A4).withValues(alpha: 0.15),
              child: const Icon(
                Icons.person,
                color: Color(0xFF8CB2A4),
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    guestName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (email != null)
                    Text(
                      email,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            _platformBadge(nextBooking.platform),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _infoChip(
              Icons.calendar_today,
              '${dateFormatter.format(nextBooking.start)} → ${dateFormatter.format(nextBooking.end)}',
              Colors.blueGrey,
            ),
            _infoChip(
              Icons.nights_stay,
              '${nextBooking.nights} night${nextBooking.nights == 1 ? '' : 's'}',
              Colors.blueGrey,
            ),
            if (arrivalTime != null)
              _infoChip(
                Icons.access_time,
                arrivalTime,
                const Color(0xFF8CB2A4),
              ),
            if (phone != null) _infoChip(Icons.phone, phone, Colors.blue),
            if (lockCode != null)
              _infoChip(Icons.lock, lockCode, const Color(0xFFC62828)),
          ],
        ),
      ],
    );
  }

  // ─── Shared widgets ───────────────────────────────────────────────────────

  Widget _infoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _platformBadge(String platform) {
    Color color;
    String label;
    if (platform == 'Airbnb') {
      color = const Color(0xFFE74C3C);
      label = '✈️ Airbnb';
    } else {
      color = const Color(0xFF2980B9);
      label = '🏨 Booking';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ─── Detail bottom sheet ──────────────────────────────────────────────────

  void _showEventDetail(BookingEvent event, {required bool isCheckin}) {
    final dateFormatter = DateFormat('dd MMM yyyy');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: false,
      useSafeArea: true,
      builder: (ctx) {
        bool _noteLoading = true;
        bool _noteSaving = false;
        final TextEditingController _noteCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (ctx2, setSheetState) {
            // Load note once
            if (_noteLoading) {
              ApiService.fetchBookingNote(event).then((n) {
                if (ctx2.mounted) {
                  setSheetState(() {
                    _noteCtrl.text = n;
                    _noteLoading = false;
                  });
                }
              });
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isCheckin
                                ? const Color(
                                    0xFF8CB2A4,
                                  ).withValues(alpha: 0.12)
                                : const Color(
                                    0xFFE57373,
                                  ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isCheckin
                                ? '✈️ Check-in Details'
                                : '🔑 Next Guest Details',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isCheckin
                                  ? const Color(0xFF8CB2A4)
                                  : const Color(0xFFE57373),
                            ),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.of(ctx2).pop(),
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
                    const SizedBox(height: 16),

                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.room,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _platformBadge(event.platform),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Notes Section ────────────────────────────────────
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.sticky_note_2_outlined,
                            size: 16,
                            color: Color(0xFFF9A825),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Notes',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[700],
                          ),
                        ),
                        const Spacer(),
                        if (_noteLoading)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF8CB2A4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDE7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFFEE58),
                          width: 1.2,
                        ),
                      ),
                      child: TextField(
                        controller: _noteCtrl,
                        minLines: 3,
                        maxLines: 6,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF212529),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add notes about this guest or booking…',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[400],
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(14),
                        ),
                        onChanged: (_) {},
                        enabled: !_noteLoading,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _noteSaving || _noteLoading
                            ? null
                            : () async {
                                setSheetState(() => _noteSaving = true);
                                final ok = await ApiService.saveBookingNote(
                                  event,
                                  _noteCtrl.text.trim(),
                                );
                                if (ctx2.mounted) {
                                  setSheetState(() => _noteSaving = false);
                                  ScaffoldMessenger.of(ctx2).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? 'Note saved ✓'
                                            : 'Failed to save note',
                                      ),
                                      backgroundColor: ok
                                          ? const Color(0xFF8CB2A4)
                                          : Colors.red,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                        icon: _noteSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: Text(_noteSaving ? 'Saving…' : 'Save Note'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8CB2A4),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Dates
                    Row(
                      children: [
                        Expanded(
                          child: _detailField(
                            'Check-in',
                            dateFormatter.format(event.start),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _detailField(
                            'Check-out',
                            dateFormatter.format(event.end),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (event.nights > 0)
                      _detailField(
                        'Duration',
                        '${event.nights} night${event.nights == 1 ? '' : 's'}',
                      ),

                    // Guest form data
                    if (event.formData.isNotEmpty) ...[
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
                            final lk = e.key.toLowerCase().replaceAll(' ', '');
                            if (lk.contains('nonce') ||
                                lk.contains('referer') ||
                                lk.contains('token') ||
                                lk.contains('hash') ||
                                lk.contains('wphttp') ||
                                lk.contains('_wp_') ||
                                lk.contains('formid') ||
                                lk.contains('__') ||
                                lk.startsWith('utm'))
                              return false;
                            return true;
                          })
                          .map((entry) {
                            final lk = entry.key.toLowerCase();
                            final isSecret =
                                lk.contains('lock') ||
                                lk.contains('code') ||
                                lk.contains('pin');
                            return _detailField(
                              entry.key,
                              entry.value.toString(),
                              isSecret: isSecret,
                            );
                          }),
                    ],

                    if (event.formData.isEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.amber[700]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No guest details found in Fluent Forms for this booking.',
                                style: TextStyle(
                                  color: Colors.amber[800],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailField(String label, String value, {bool isSecret = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSecret ? const Color(0xFFFFF5F5) : const Color(0xFFF8F9FA),
        border: Border.all(
          color: isSecret ? const Color(0xFFFFCDD2) : const Color(0xFFE9ECEF),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSecret ? '🔐 $label' : label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: isSecret ? const Color(0xFFC62828) : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isSecret ? 17 : 15,
              fontWeight: isSecret ? FontWeight.w800 : FontWeight.w500,
              letterSpacing: isSecret ? 2 : 0,
              fontFamily: isSecret ? 'monospace' : null,
              color: isSecret
                  ? const Color(0xFFC62828)
                  : const Color(0xFF212529),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class _CheckinEntry {
  final String calendarName;
  final BookingEvent event;
  _CheckinEntry({required this.calendarName, required this.event});
}

class _CheckoutEntry {
  final String calendarName;
  final BookingEvent checkoutEvent;
  final BookingEvent? nextBooking;
  _CheckoutEntry({
    required this.calendarName,
    required this.checkoutEvent,
    this.nextBooking,
  });
}
