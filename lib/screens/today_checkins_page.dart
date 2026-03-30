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

  @override
  void initState() {
    super.initState();
    _fetchData();
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

  /// Get all events checking in today across all calendars, paired with calendar name.
  List<_CheckinEntry> get _todayCheckins {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entries = <_CheckinEntry>[];

    for (final cal in _calendars) {
      for (final event in cal.events) {
        final startDate = DateTime(event.start.year, event.start.month, event.start.day);
        if (startDate.isAtSameMomentAs(today) && !event.isBlocked) {
          entries.add(_CheckinEntry(calendarName: cal.name, event: event));
        }
      }
    }

    return entries;
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
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  child: _buildBody(),
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
              onPressed: _fetchData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8CB2A4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final checkins = _todayCheckins;
    final now = DateTime.now();
    final todayFormatted = DateFormat('EEEE, dd MMMM yyyy').format(now);

    if (checkins.isEmpty) {
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
                    'No Check-ins Today',
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
                    'No guests are arriving today.',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Group check-ins by calendar
    final grouped = <String, List<_CheckinEntry>>{};
    for (final entry in checkins) {
      grouped.putIfAbsent(entry.calendarName, () => []).add(entry);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Today header
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
                child: const Icon(Icons.flight_land, color: Colors.white, size: 26),
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
                      '${checkins.length} Check-in${checkins.length == 1 ? '' : 's'} Today',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${checkins.length}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Grouped check-in cards
        ...grouped.entries.map((entry) {
          final calName = entry.key;
          final calCheckins = entry.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  calName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              ...calCheckins.map((ci) => _buildCheckinCard(ci.event)),
              const SizedBox(height: 12),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildCheckinCard(BookingEvent event) {
    final bgColor = _parseColor(event.backgroundColor);
    final dateFormatter = DateFormat('dd MMM');
    final guestName = _getGuestName(event.formData);
    final arrivalTime = _getGuestField(event.formData, ['arrival', 'time', 'checkin']);
    final lockCode = _getGuestField(event.formData, ['lock', 'code', 'pin']);
    final email = _getGuestField(event.formData, ['email', 'mail']);
    final phone = _getGuestField(event.formData, ['phone', 'mobile', 'tel']);

    return GestureDetector(
      onTap: () => _showCheckinDetail(event),
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
          border: Border(
            left: BorderSide(color: bgColor, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: room name + platform badge
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

              // Guest info row
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
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // Nights badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${event.nights}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'night${event.nights == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Date + details chips row
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
                    _infoChip(Icons.access_time, arrivalTime, const Color(0xFF8CB2A4)),
                  if (phone != null)
                    _infoChip(Icons.phone, phone, Colors.blue),
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
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
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
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  // ─── Detail bottom sheet ──────────────────────────────────────

  void _showCheckinDetail(BookingEvent event) {
    final dateFormatter = DateFormat('dd MMM yyyy');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
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
                // Close button
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
                        child: Icon(Icons.close, size: 20, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Title row
                Row(
                  children: [
                    Expanded(
                      child: Text(event.room,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    _platformBadge(event.platform),
                  ],
                ),
                const SizedBox(height: 20),

                // Dates row
                Row(
                  children: [
                    Expanded(
                      child: _detailField(
                          'Check-in', dateFormatter.format(event.start)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _detailField(
                          'Check-out', dateFormatter.format(event.end)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (event.nights > 0)
                  _detailField('Duration',
                      '${event.nights} night${event.nights == 1 ? '' : 's'}'),

                // Form data (guest details)
                if (event.formData.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Guest Details',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[500])),
                  const SizedBox(height: 10),
                  ...event.formData.entries
                      .where((e) {
                        if (e.value == null || e.value.toString().isEmpty) {
                          return false;
                        }
                        final lk = e.key.toLowerCase().replaceAll(' ', '');
                        if (lk.contains('nonce') ||
                            lk.contains('referer') ||
                            lk.contains('token') ||
                            lk.contains('hash') ||
                            lk.contains('wphttp') ||
                            lk.contains('fluentform') && lk.contains('nonce') ||
                            lk.contains('_wp_') ||
                            lk.contains('formid') ||
                            lk.contains('__') ||
                            lk.startsWith('utm')) {
                          return false;
                        }
                        return true;
                      })
                      .map((entry) {
                    final lk = entry.key.toLowerCase();
                    final isSecret = lk.contains('lock') ||
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
                            'No guest details found in Fluent Forms for this check-in date.',
                            style: TextStyle(
                                color: Colors.amber[800], fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),
              ],
            ),
          ),
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
            color:
                isSecret ? const Color(0xFFFFCDD2) : const Color(0xFFE9ECEF)),
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

class _CheckinEntry {
  final String calendarName;
  final BookingEvent event;

  _CheckinEntry({required this.calendarName, required this.event});
}
