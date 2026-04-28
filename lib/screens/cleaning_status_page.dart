import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:wild_atlantic_hub/models/apartment.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';
import 'package:wild_atlantic_hub/screens/status_details_page.dart';
import 'package:wild_atlantic_hub/models/cleaning_details.dart';

class CleaningStatusPage extends StatefulWidget {
  const CleaningStatusPage({super.key});
  @override
  State<CleaningStatusPage> createState() => _CleaningStatusPageState();
}

class _CleaningStatusPageState extends State<CleaningStatusPage> with WidgetsBindingObserver {
  List<Apartment> _apartments = [];
  final Map<String, String> _cleaningStatus = {};
  final Map<String, bool> _isLoading = {};
  final Map<String, int> _ratings = {};

  // State maps
  final Map<String, String> _lastRatedAts = {};
  final Map<String, TextEditingController> _remarksControllers = {};
  final Map<String, File?> _selectedImages = {};
  final Map<String, String> _existingImageUrls = {};
  final Map<String, String> _startTimes = {};
  final Map<String, String> _endTimes = {};
  final Map<String, List<RatingHistoryEntry>> _ratingHistories = {};

  // Track which apartment card is expanded
  final Map<String, bool> _expandedCards = {};

  bool _isFetchingInitialData = true;
  DateTime _lastKnownRealDate = DateTime.now();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeStatuses();
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkDateChange();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    for (var controller in _remarksControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _checkDateChange() {
    final now = DateTime.now();
    if (now.day != _lastKnownRealDate.day ||
        now.month != _lastKnownRealDate.month ||
        now.year != _lastKnownRealDate.year) {
      _lastKnownRealDate = now;
      _initializeStatuses();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDateChange();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkDateChange();
  }

  Future<void> _initializeStatuses({bool silent = false}) async {
    if (mounted && !silent) {
      setState(() {
        _isFetchingInitialData = true;
      });
    }

    try {
      final List<CleaningDetails> detailsList =
          await ApiService.fetchCleaningDetails();

      bool needsApiRefresh = false;

      // Automatically evaluate checkouts against the implicitly generated 'cleaned' statuses
      try {
        final calendars = await ApiService.fetchBookingCalendars();
        final targetDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

        // helper for matching names
        String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
        bool _isRoomMatched(String a, String b) {
          final aNorm = _normalize(a);
          final bNorm = _normalize(b);
          if (aNorm.isEmpty || bNorm.isEmpty) return false;
          if (aNorm == bNorm) return true;
          return RegExp(r'\b' + RegExp.escape(aNorm) + r'\b').hasMatch(bNorm) || 
                 RegExp(r'\b' + RegExp.escape(bNorm) + r'\b').hasMatch(aNorm);
        }

        for (final detail in detailsList) {
           // 'N/A' means the backend carried over the status from yesterday but no work has been done yet today
           if (detail.status.toLowerCase() == 'cleaned' && detail.startTime == 'N/A' && detail.endTime == 'N/A') {
              bool isOccupied = false;
              for (final cal in calendars) {
                  for (final ev in cal.events) {
                      if (ev.isBlocked) continue;
                      if (!_isRoomMatched(ev.room, detail.name)) continue;

                      final start = DateTime(ev.start.year, ev.start.month, ev.start.day);
                      final end = DateTime(ev.end.year, ev.end.month, ev.end.day);

                      // Either checking out today, or spanning completely through today
                      if (end.isAtSameMomentAs(targetDay) || (!start.isAfter(targetDay) && end.isAfter(targetDay))) {
                         isOccupied = true;
                         break;
                      }
                  }
                  if (isOccupied) break;
              }

              if (isOccupied) {
                 await ApiService.updateCleaningStatus(apartmentId: detail.id, statusToSend: 'reset', rating: 0);
                 needsApiRefresh = true;
              }
           }
        }
      } catch (e) {
        // Ignored, calendar parsing failed but we should proceed to render available data
      }

      if (needsApiRefresh) {
        final renewedDetailsList = await ApiService.fetchCleaningDetails();
        detailsList.clear();
        detailsList.addAll(renewedDetailsList);
      }

      if (mounted) {
        setState(() {
          _apartments = detailsList
              .map(
                (d) => Apartment(id: d.id, name: d.name, imageUrl: d.imageUrl),
              )
              .toList();

          for (final detail in detailsList) {
            _cleaningStatus[detail.id] = detail.status;
            _isLoading[detail.id] = false;
            _ratings[detail.id] = detail.rating;
            _lastRatedAts[detail.id] = detail.lastRatedAt;
            _existingImageUrls[detail.id] = detail.cleaningImageUrl;
            _startTimes[detail.id] = detail.startTime;
            _endTimes[detail.id] = detail.endTime;
            _ratingHistories[detail.id] = detail.ratingHistory;

            if (!_expandedCards.containsKey(detail.id)) {
              _expandedCards[detail.id] = false;
            }

            if (!_remarksControllers.containsKey(detail.id)) {
              _remarksControllers[detail.id] =
                  TextEditingController(text: detail.remarks);
            } else {
              _remarksControllers[detail.id]!.text = detail.remarks;
            }
          }
        });
        await _fetchStatusesFromServer();
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Error fetching apartment list. Please try again.',
          Colors.red,
        );
      }
    } finally {
      if (mounted && !silent) {
        setState(() {
          _isFetchingInitialData = false;
        });
      }
    }
  }

  Future<void> _fetchStatusesFromServer() async {
    try {
      final serverStatuses = await ApiService.fetchCleaningStatuses();
      if (mounted) {
        setState(() {
          serverStatuses.forEach((aptId, status) {
            if (_cleaningStatus.containsKey(aptId)) {
              _cleaningStatus[aptId] = status;
            }
          });
        });
      }
    } catch (e) {
      _showSnackBar(
        'Error connecting to server to fetch statuses.',
        Colors.red,
      );
    }
  }

  Future<void> _showCleaningTimePicker(String apartmentId) async {
    final int? selectedDuration = await showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          title: const Text(
            'Estimated Cleaning Time',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 45),
              child: const Text('45 mins'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 60),
              child: const Text('1 hour'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 75),
              child: const Text('1 hour 15 mins'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 90),
              child: const Text('1 hour 30 mins'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 105),
              child: const Text('1 hour 45 mins'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 120),
              child: const Text('2 hours'),
            ),
          ],
        );
      },
    );
    if (selectedDuration != null) {
      _updateStatus(apartmentId, 'start', durationMinutes: selectedDuration);
    }
  }

  Future<void> _showResetConfirmation(Apartment apartment) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Reset', style: TextStyle(fontSize: 16)),
        content: Text(
          'Reset all cleaning data for ${apartment.name} today?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _updateStatus(apartment.id, 'reset');
    }
  }

  Future<void> _updateRating(String apartmentId, int newRating) async {
    if (!mounted) return;

    final originalRating = _ratings[apartmentId];
    setState(() {
      _isLoading[apartmentId] = true;
      _ratings[apartmentId] = newRating;
    });

    try {
      final response = await ApiService.updateCleaningRating(
        apartmentId: apartmentId,
        rating: newRating,
      );

      if (response.statusCode != 200) {
        final responseBody = json.decode(response.body);
        final errorMessage =
            responseBody['message'] ?? 'An unknown error occurred.';
        _showSnackBar('Error: $errorMessage', Colors.red);
        if (mounted) {
          setState(() {
            _ratings[apartmentId] = originalRating!;
          });
        }
      } else {
        _showSnackBar('Rating updated!', Colors.green);
        // Update the last rated timestamp immediately
        if (mounted) {
          setState(() {
            _lastRatedAts[apartmentId] =
                DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
          });
        }
        // If rating is low (<=2), show feedback requirement hint
        if (newRating <= 2) {
          _showSnackBar(
            'Low rating — please add remarks below.',
            Colors.orange,
          );
        }
      }
    } catch (e) {
      _showSnackBar('Failed to connect. Check your connection.', Colors.red);
      if (mounted) {
        setState(() {
          _ratings[apartmentId] = originalRating!;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading[apartmentId] = false;
        });
      }
    }
  }

  Future<void> _updateStatus(
    String apartmentId,
    String statusToSend, {
    int? durationMinutes,
  }) async {
    if (!mounted) return;

    setState(() {
      _isLoading[apartmentId] = true;
    });

    try {
      final response = await ApiService.updateCleaningStatus(
        apartmentId: apartmentId,
        statusToSend: statusToSend,
        rating: _ratings[apartmentId] ?? 0,
        durationMinutes: durationMinutes,
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            if (statusToSend == 'start') {
              _cleaningStatus[apartmentId] = 'in_progress';
              // Update start time to now
              _startTimes[apartmentId] =
                  DateFormat('hh:mm a').format(DateTime.now());
              _endTimes[apartmentId] = 'N/A';
            } else if (statusToSend == 'stop') {
              _cleaningStatus[apartmentId] = 'cleaned';
              // Update end time to now
              _endTimes[apartmentId] =
                  DateFormat('hh:mm a').format(DateTime.now());
            } else if (statusToSend == 'reset') {
              _cleaningStatus[apartmentId] = 'not_cleaned';
              _ratings[apartmentId] = 0;
              _startTimes[apartmentId] = 'N/A';
              _endTimes[apartmentId] = 'N/A';
              _lastRatedAts[apartmentId] = '';
              _remarksControllers[apartmentId]?.text = '';
              _selectedImages[apartmentId] = null;
              _existingImageUrls[apartmentId] = '';
            }
          });
        }
        _showSnackBar('Status updated successfully!', Colors.green);
      } else {
        final responseBody = json.decode(response.body);
        final errorMessage =
            responseBody['message'] ?? 'An unknown error occurred.';
        _showSnackBar('Error: $errorMessage', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Failed to connect. Check your connection.', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading[apartmentId] = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickImage(String apartmentId) async {
    final picker = ImagePicker();
    try {
      final pickedFile =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (pickedFile != null) {
        setState(() {
          _selectedImages[apartmentId] = File(pickedFile.path);
        });
      }
    } catch (e) {
      _showSnackBar('Failed to pick image.', Colors.red);
    }
  }

  void _showFullScreenImage(ImageProvider imageProvider, String title) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image(
                  image: imageProvider,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image, color: Colors.white54, size: 48),
                        SizedBox(height: 8),
                        Text('Failed to load image',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
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
    );
  }

  Future<void> _saveFeedback(String apartmentId) async {
    if (!mounted) return;

    final int currentRating = _ratings[apartmentId] ?? 0;
    final String remarks = _remarksControllers[apartmentId]?.text ?? '';

    // Validate: if rating is low (<=2), remarks are required
    if (currentRating > 0 && currentRating <= 2 && remarks.trim().isEmpty) {
      _showSnackBar(
        'Remarks are required for ratings of 2 stars or below.',
        Colors.orange,
      );
      return;
    }

    setState(() {
      _isLoading[apartmentId] = true;
    });

    try {
      String? base64Image;
      if (_selectedImages[apartmentId] != null) {
        final bytes = await _selectedImages[apartmentId]!.readAsBytes();
        base64Image = base64Encode(bytes);
      }

      final response = await ApiService.updateCleaningFeedback(
        apartmentId: apartmentId,
        remarks: remarks,
        base64Image: base64Image,
      );

      if (response.statusCode == 200) {
        _showSnackBar('Feedback saved successfully!', Colors.green);
        // Try to extract uploaded image URL from response
        try {
          final responseBody = json.decode(response.body);
          if (responseBody['image_url'] != null &&
              responseBody['image_url'].toString().isNotEmpty) {
            setState(() {
              _existingImageUrls[apartmentId] = responseBody['image_url'];
            });
          }
        } catch (_) {}
        setState(() {
          _selectedImages[apartmentId] = null;
        });
      } else {
        final responseBody = json.decode(response.body);
        final errorMessage =
            responseBody['message'] ?? 'An unknown error occurred.';
        _showSnackBar('Error: $errorMessage', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Failed to connect. Check your connection.', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading[apartmentId] = false;
        });
      }
    }
  }

  // ─── Status helpers ──────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'in_progress':
        return Colors.orange;
      case 'cleaned':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'In Progress';
      case 'cleaned':
        return 'Cleaned';
      default:
        return 'Not Cleaned';
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'in_progress':
        return Icons.timelapse;
      case 'cleaned':
        return Icons.check_circle;
      default:
        return Icons.circle_outlined;
    }
  }

  // ─── Build Widgets ───────────────────────────────────────

  Widget _buildCompactStarRating(String apartmentId) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final ratingValue = index + 1;
        return GestureDetector(
          onTap: () => _updateRating(apartmentId, ratingValue),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              (_ratings[apartmentId] ?? 0) >= ratingValue
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: Colors.amber.shade600,
              size: 28,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTimingRow(String apartmentId) {
    final start = _startTimes[apartmentId] ?? 'N/A';
    final end = _endTimes[apartmentId] ?? 'N/A';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(Icons.play_circle_outline,
                    size: 16, color: Colors.green.shade600),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Started',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500)),
                    Text(start,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          Container(width: 1, height: 28, color: Colors.grey.shade300),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Finished',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500)),
                    Text(end,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(width: 6),
                Icon(Icons.stop_circle_outlined,
                    size: 16, color: Colors.red.shade400),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _tryParseHistoryDate(String raw) {
    if (raw.isEmpty) return null;
    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;
    // Try common display formats like "dd/MM/yyyy" or "dd-MM-yyyy" with optional time
    final m = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})(?:[\sT]+(\d{1,2}):(\d{2}))?').firstMatch(raw);
    if (m != null) {
      int day = int.parse(m.group(1)!);
      int month = int.parse(m.group(2)!);
      int year = int.parse(m.group(3)!);
      if (year < 100) year += 2000;
      int hour = m.group(4) != null ? int.parse(m.group(4)!) : 0;
      int minute = m.group(5) != null ? int.parse(m.group(5)!) : 0;
      try {
        return DateTime(year, month, day, hour, minute);
      } catch (_) {}
    }
    return null;
  }

  Widget _buildRatingHistorySection(String apartmentId) {
    final rawHistory = _ratingHistories[apartmentId] ?? [];

    // Sort by parsed date descending so the most recent ratings show first,
    // regardless of backend order or whether remarks are present. Entries
    // with unparseable dates retain their original relative order at the end.
    final indexed = List.generate(rawHistory.length, (i) => MapEntry(i, rawHistory[i])).toList();
    indexed.sort((a, b) {
      final da = _tryParseHistoryDate(a.value.date);
      final db = _tryParseHistoryDate(b.value.date);
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      // Backend already returns newest-first; preserve that order on ties.
      return a.key.compareTo(b.key);
    });
    final history = indexed.map((e) => e.value).toList();

    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Text(
          'No previous rating history available.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade400,
              fontStyle: FontStyle.italic),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            onExpansionChanged: (isExpanded) {
              if (isExpanded) {
                // Fetch latest data silently when dropdown is opened
                _initializeStatuses(silent: true);
              }
            },
            title: Row(
              children: [
                Icon(Icons.history, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  'Previous Rating History',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            children: history.take(3).map((entry) => Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.date,
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade700),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(5, (i) {
                            return Icon(
                              i < entry.rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 14,
                              color: Colors.amber.shade600,
                            );
                          }),
                        ),
                      ],
                    ),
                    if (entry.remarks.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        entry.remarks,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                    if (entry.imageUrl != null && entry.imageUrl!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          _showFullScreenImage(
                            NetworkImage(entry.imageUrl!),
                            'History Photo',
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            entry.imageUrl!,
                            height: 80,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview(String apartmentId) {
    final File? localImage = _selectedImages[apartmentId];
    final String serverUrl = _existingImageUrls[apartmentId] ?? '';
    final bool hasLocalImage = localImage != null;
    final bool hasServerImage = serverUrl.isNotEmpty;

    if (!hasLocalImage && !hasServerImage) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                hasLocalImage ? 'Photo to Upload' : 'Uploaded Photo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              if (hasLocalImage)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedImages[apartmentId] = null;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 12, color: Colors.red.shade400),
                        const SizedBox(width: 2),
                        Text('Remove',
                            style: TextStyle(
                                fontSize: 10, color: Colors.red.shade400)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              if (hasLocalImage) {
                _showFullScreenImage(
                  FileImage(localImage),
                  'Photo Preview',
                );
              } else if (hasServerImage) {
                _showFullScreenImage(
                  NetworkImage(serverUrl),
                  'Uploaded Photo',
                );
              }
            },
            child: Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
                color: Colors.grey.shade100,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasLocalImage)
                    Image.file(
                      localImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.grey, size: 32),
                      ),
                    )
                  else if (hasServerImage)
                    Image.network(
                      serverUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image,
                                color: Colors.grey, size: 28),
                            SizedBox(height: 4),
                            Text('Could not load image',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  // Tap-to-preview overlay
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in, size: 13, color: Colors.white),
                          SizedBox(width: 4),
                          Text('Tap to preview',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackSection(String apartmentId) {
    final int currentRating = _ratings[apartmentId] ?? 0;
    final bool isLowRating = currentRating > 0 && currentRating <= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Remarks',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            if (isLowRating) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Required',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _remarksControllers[apartmentId],
          maxLines: 2,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: isLowRating
                ? 'Please describe the issues found...'
                : 'Optional remarks on cleanliness...',
            hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF8CB2A4)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(apartmentId),
                icon: const Icon(Icons.camera_alt_outlined, size: 15),
                label: Text(
                  _selectedImages[apartmentId] != null
                      ? 'Change Photo'
                      : 'Add Photo',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _selectedImages[apartmentId] != null
                      ? Colors.green
                      : Colors.blueGrey,
                  side: BorderSide(
                    color: _selectedImages[apartmentId] != null
                        ? Colors.green
                        : Colors.blueGrey.shade300,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading[apartmentId] == true
                    ? null
                    : () => _saveFeedback(apartmentId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8CB2A4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 0,
                ),
                child:
                    const Text('Save Feedback', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        // Image preview (local or server)
        _buildImagePreview(apartmentId),
      ],
    );
  }

  Widget _buildActionButton(
    Apartment apartment,
    String status,
    bool isLoading,
    int rating,
  ) {
    String buttonText;
    Color buttonColor;
    IconData buttonIcon;
    VoidCallback? onPressedAction;
    bool isButtonDisabled =
        isLoading || (status == 'not_cleaned' && rating == 0);

    switch (status) {
      case 'in_progress':
        buttonText = 'Finish Cleaning';
        buttonColor = const Color(0xFFE57373);
        buttonIcon = Icons.stop_rounded;
        onPressedAction = () => _updateStatus(apartment.id, 'stop');
        break;
      case 'cleaned':
        buttonText = 'Resume Cleaning';
        buttonColor = const Color(0xFFF7C59F);
        buttonIcon = Icons.replay_rounded;
        onPressedAction = () => _updateStatus(apartment.id, 'start');
        break;
      default:
        buttonText = 'Start Cleaning';
        buttonColor = const Color(0xFF8CB2A4);
        buttonIcon = Icons.play_arrow_rounded;
        onPressedAction = () => _showCleaningTimePicker(apartment.id);
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isButtonDisabled ? null : onPressedAction,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(buttonIcon, size: 18),
        label: Text(buttonText, style: const TextStyle(fontSize: 14)),
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade400,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildApartmentCard(Apartment apartment) {
    final String status = _cleaningStatus[apartment.id] ?? 'not_cleaned';
    final bool isLoading = _isLoading[apartment.id] ?? false;
    final int rating = _ratings[apartment.id] ?? 0;
    final bool isExpanded = _expandedCards[apartment.id] ?? false;
    final Color statColor = _statusColor(status);

    return Card(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          // ─── Collapsed header (always visible) ───
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _expandedCards[apartment.id] = !isExpanded;
              });
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Apartment image
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: apartment.imageUrl.isNotEmpty
                        ? NetworkImage(apartment.imageUrl)
                        : null,
                    child: apartment.imageUrl.isEmpty
                        ? Icon(Icons.apartment,
                            size: 20, color: Colors.grey.shade400)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Apartment name + status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          apartment.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(_statusIcon(status),
                                size: 11, color: statColor),
                            const SizedBox(width: 4),
                            Text(
                              _statusLabel(status),
                              style: TextStyle(
                                fontSize: 10,
                                color: statColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (rating > 0) ...[
                              const SizedBox(width: 10),
                              ...List.generate(
                                5,
                                (i) => Icon(
                                  i < rating
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  size: 12,
                                  color: Colors.amber.shade600,
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Last Updated date
                        if ((_lastRatedAts[apartment.id] ?? '').isNotEmpty &&
                            _lastRatedAts[apartment.id] != 'Unknown')
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Last Updated: ${_lastRatedAts[apartment.id]}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Reset button (only when in_progress or cleaned)
                  if (status != 'not_cleaned' && !isLoading)
                    GestureDetector(
                      onTap: () => _showResetConfirmation(apartment),
                      child: Icon(Icons.refresh,
                          size: 18, color: Colors.grey.shade400),
                    ),
                  const SizedBox(width: 8),
                  // Dropdown arrow
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 22, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ),

          // ─── Expanded content ───
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Colors.grey.shade100, height: 1),
                  const SizedBox(height: 12),

                  // Timing row
                  _buildTimingRow(apartment.id),
                  const SizedBox(height: 10),

                  // Last Updated
                  Row(
                    children: [
                      Icon(Icons.update_rounded,
                          size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 5),
                      Text(
                        'Last Updated: ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      Text(
                        (_lastRatedAts[apartment.id] ?? '').isNotEmpty &&
                                _lastRatedAts[apartment.id] != 'Unknown'
                            ? _lastRatedAts[apartment.id]!
                            : 'No rating given yet',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Star rating
                  Row(
                    children: [
                      Text(
                        "Today's Rating",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildCompactStarRating(apartment.id),
                    ],
                  ),
                  if ((_lastRatedAts[apartment.id] ?? '').isNotEmpty &&
                      _lastRatedAts[apartment.id] != 'Unknown')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            'Last rated: ${_lastRatedAts[apartment.id]}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Rating history
                  _buildRatingHistorySection(apartment.id),

                  // Feedback section (remarks + photo)
                  _buildFeedbackSection(apartment.id),

                  const SizedBox(height: 14),

                  // Action button
                  _buildActionButton(apartment, status, isLoading, rating),
                ],
              ),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cleaning',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF8CB2A4),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined, color: Colors.white,
                size: 22),
            tooltip: 'View Status Details',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const StatusDetailsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
              onRefresh: _initializeStatuses,
              color: const Color(0xFF8CB2A4),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 8.0,
                ),
                itemCount: _apartments.length,
                itemBuilder: (context, index) {
                  return _buildApartmentCard(_apartments[index]);
                },
              ),
            ),
    );
  }
}