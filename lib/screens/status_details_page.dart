import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wild_atlantic_hub/models/cleaning_details.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';

class StatusDetailsPage extends StatefulWidget {
  const StatusDetailsPage({super.key});

  @override
  State<StatusDetailsPage> createState() => _StatusDetailsPageState();
}

class _StatusDetailsPageState extends State<StatusDetailsPage> {
  late Future<List<CleaningDetails>> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = ApiService.fetchCleaningDetails();
  }

  Future<List<CleaningDetails>> _refresh() {
    setState(() {
      _detailsFuture = ApiService.fetchCleaningDetails();
    });
    return _detailsFuture;
  }

  // ─── Helpers ─────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'cleaned':
        return const Color(0xFF4CAF50);
      case 'in_progress':
      case 'in progress':
        return const Color(0xFFFF8F00);
      default:
        return const Color(0xFF90A4AE);
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'cleaned':
        return Icons.check_circle_rounded;
      case 'in_progress':
      case 'in progress':
        return Icons.timelapse_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'cleaned':
        return 'Cleaned';
      case 'in_progress':
      case 'in progress':
        return 'In Progress';
      default:
        return 'Not Cleaned';
    }
  }

  String _todayDate() {
    return DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'Current Status',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF8CB2A4),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF8CB2A4),
        child: FutureBuilder<List<CleaningDetails>>(
          future: _detailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('Error: ${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No status details available.'));
            }

            final detailsList = snapshot.data!;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Date header
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8CB2A4).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color:
                            const Color(0xFF8CB2A4).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 15, color: Color(0xFF6D9B8C)),
                      const SizedBox(width: 8),
                      Text(
                        _todayDate(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4A7A6D),
                        ),
                      ),
                    ],
                  ),
                ),

                // Apartment cards
                ...detailsList.map((details) =>
                    _buildApartmentCard(details)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildApartmentCard(CleaningDetails details) {
    final statusColor = _statusColor(details.status);
    final statusLabel = _statusLabel(details.status);
    final statusIcon = _statusIcon(details.status);

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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(
                    color: statusColor.withValues(alpha: 0.18), width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.apartment_rounded,
                    size: 18, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    details.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Body ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Cleaning Date
                _infoRow(
                  icon: Icons.calendar_month_rounded,
                  iconColor: const Color(0xFF6C63FF),
                  label: 'Cleaning Date',
                  value: _todayDate(),
                ),
                _divider(),

                // Cleaning Started / Finished in one row
                Row(
                  children: [
                    Expanded(
                      child: _infoBlock(
                        icon: Icons.play_circle_outline_rounded,
                        iconColor: const Color(0xFF4CAF50),
                        label: 'Cleaning Started',
                        value: details.startTime.isNotEmpty &&
                                details.startTime != 'N/A'
                            ? details.startTime
                            : '—',
                      ),
                    ),
                    Container(
                        width: 1, height: 48, color: Colors.grey.shade100),
                    Expanded(
                      child: _infoBlock(
                        icon: Icons.stop_circle_outlined,
                        iconColor: const Color(0xFFE57373),
                        label: 'Cleaning Ending',
                        value: details.endTime.isNotEmpty &&
                                details.endTime != 'N/A'
                            ? details.endTime
                            : '—',
                        alignRight: true,
                      ),
                    ),
                  ],
                ),
                _divider(),

                // Duration
                _infoRow(
                  icon: Icons.hourglass_bottom_rounded,
                  iconColor: const Color(0xFFFF8F00),
                  label: 'Duration',
                  value: details.duration.isNotEmpty &&
                          details.duration != 'N/A'
                      ? details.duration
                      : '—',
                ),
                _divider(),

                // Star Rating
                _ratingRow(details.rating),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBlock({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    bool alignRight = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          alignRight ? 16 : 0, 10, alignRight ? 0 : 16, 10),
      child: Column(
        crossAxisAlignment:
            alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: alignRight
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (!alignRight) ...[
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (alignRight) ...[
                const SizedBox(width: 5),
                Icon(icon, size: 14, color: iconColor),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingRow(int rating) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(Icons.star_rounded, size: 16, color: Colors.amber.shade700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Rating',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (rating == 0)
            Text(
              'Not rated yet',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade400,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                return Icon(
                  i < rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: Colors.amber.shade600,
                  size: 20,
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(color: Colors.grey.shade100, height: 1);
}
