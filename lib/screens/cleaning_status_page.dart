import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:wild_atlantic_hub/models/apartment.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';
import 'package:wild_atlantic_hub/screens/status_details_page.dart';
import 'package:wild_atlantic_hub/models/cleaning_details.dart';

class CleaningStatusPage extends StatefulWidget {
  const CleaningStatusPage({super.key});
  @override
  State<CleaningStatusPage> createState() => _CleaningStatusPageState();
}

class _CleaningStatusPageState extends State<CleaningStatusPage> {
  List<Apartment> _apartments = [];
  final Map<String, String> _cleaningStatus = {};
  final Map<String, bool> _isLoading = {};
  final Map<String, int> _ratings = {};
  bool _isFetchingInitialData = true;

  @override
  void initState() {
    super.initState();
    _initializeStatuses();
  }

  Future<void> _initializeStatuses() async {
    if (mounted) {
      setState(() {
        _isFetchingInitialData = true;
      });
    }

    try {
      final List<CleaningDetails> detailsList =
          await ApiService.fetchCleaningDetails();
      if (mounted) {
        setState(() {
          _apartments = detailsList
              .map(
                (d) => Apartment(id: d.id, name: d.name, imageUrl: d.imageUrl),
              )
              .toList();

          // Initialize local state from the fetched details
          for (final detail in detailsList) {
            _cleaningStatus[detail.id] = 'not_cleaned'; // Default value
            _isLoading[detail.id] = false;
            _ratings[detail.id] = detail.rating; // Use rating from server
          }
        });
        await _fetchStatusesFromServer(); // Overwrite with live statuses
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Error fetching apartment list. Please try again.',
          Colors.red,
        );
      }
    } finally {
      if (mounted) {
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
            borderRadius: BorderRadius.circular(20),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          title: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(child: Text('Estimated Cleaning Time')),
              Positioned(
                top: -16,
                right: -16,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
        title: Stack(
          clipBehavior: Clip.none,
          children: [
            const Text('Confirm Reset'),
            Positioned(
              top: -16,
              right: -16,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to reset all cleaning data for ${apartment.name} today?',
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
      _ratings[apartmentId] = newRating; // Optimistic UI update
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
            _ratings[apartmentId] = originalRating!; // Rollback on error
          });
        }
      } else {
        _showSnackBar('Rating updated!', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Failed to connect. Check your connection.', Colors.red);
      if (mounted) {
        setState(() {
          _ratings[apartmentId] = originalRating!; // Rollback on error
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
            } else if (statusToSend == 'stop') {
              _cleaningStatus[apartmentId] = 'cleaned';
            } else if (statusToSend == 'reset') {
              _cleaningStatus[apartmentId] = 'not_cleaned';
              _ratings[apartmentId] = 0;
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
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

<<<<<<< Updated upstream
  Widget _buildStarRating(String apartmentId) {
=======
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

  Future<void> _saveFeedback(String apartmentId, {bool silent = false}) async {
    if (!mounted) return;

    final int currentRating = _ratings[apartmentId] ?? 0;
    final String remarks = _remarksControllers[apartmentId]?.text ?? '';

    // Validate: if rating is low (<=2), remarks are required
    if (currentRating > 0 && currentRating <= 2 && remarks.trim().isEmpty) {
      if (!silent) {
        _showSnackBar(
          'Remarks are required for ratings of 2 stars or below.',
          Colors.orange,
        );
      }
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

      if (currentRating > 0) {
        try {
          await ApiService.updateCleaningRating(
            apartmentId: apartmentId,
            rating: currentRating,
          );
        } catch (_) {}
      }

      if (response.statusCode == 200) {
        if (!silent) _showSnackBar('Feedback saved successfully!', Colors.green);
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
        if (!silent) _showSnackBar('Error: $errorMessage', Colors.red);
      }
    } catch (e) {
      if (!silent) _showSnackBar('Failed to connect. Check your connection.', Colors.red);
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
          child: Material(
            color: Colors.transparent,
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
      ),
    );
  }

  Widget _buildStartChecklistDisplay(String apartmentId) {
    final data = _checklists[apartmentId];
    if (data == null || !data.containsKey('collected_parking_pass_start')) {
      return const SizedBox.shrink();
    }
    
    final bool collected = data['collected_parking_pass_start'] == true || data['collected_parking_pass_start'] == 1;
    
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blueGrey.shade100),
        ),
        child: Row(
          children: [
            Icon(Icons.local_parking, size: 16, color: Colors.blueGrey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Have you collected the parking pass?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey.shade700,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  collected ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: collected ? const Color(0xFF4CAF50) : Colors.red.shade400,
                ),
                const SizedBox(width: 4),
                Text(
                  collected ? 'Yes' : 'No',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: collected ? const Color(0xFF4CAF50) : Colors.red.shade400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistDisplay(String apartmentId) {
    final data = _checklists[apartmentId] ?? {
      'towels_left_on_bed': 0,
      'code_set': false,
      'parking_pass_checked': false,
      'water_filled': false,
      'mirror_lights_blue': false,
    };

    final towels = (data['towels_left_on_bed'] is int)
        ? data['towels_left_on_bed'] as int
        : int.tryParse('${data['towels_left_on_bed'] ?? 0}') ?? 0;
    final codeSet = data['code_set'] == true || data['code_set'] == 1;
    final parkingPass =
        data['parking_pass_checked'] == true || data['parking_pass_checked'] == 1;
    final waterFilled = data['water_filled'] == true || data['water_filled'] == 1;
    final mirrorLightsBlue = data['mirror_lights_blue'] == true || data['mirror_lights_blue'] == 1;

    Widget row(IconData icon, String label, Widget trailing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
            trailing,
          ],
        ),
      );
    }

    Widget yesNo(bool v) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              v ? Icons.check_circle : Icons.cancel,
              size: 14,
              color: v ? const Color(0xFF8CB2A4) : Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
            Text(
              v ? 'Yes' : 'No',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: v ? const Color(0xFF8CB2A4) : Colors.grey.shade500,
              ),
            ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_rounded,
                    size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'Finish Cleaning Checklist',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            row(
              Icons.king_bed_outlined,
              'Towels left on bed',
              Text(
                '$towels',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            row(Icons.lock_outline, 'Code set', yesNo(codeSet)),
            row(Icons.local_parking, 'Parking pass in place', yesNo(parkingPass)),
            row(Icons.water_drop_outlined, 'Water filled', yesNo(waterFilled)),
            row(Icons.lightbulb_outline, 'Mirror lights are blue', yesNo(mirrorLightsBlue)),
          ],
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
        onPressedAction = () => _showFinishCleaningChecklist(apartment);
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
        onPressedAction = () => _showStartCleaningPopup(apartment);
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
              final willExpand = !isExpanded;
              setState(() {
                _expandedCards[apartment.id] = willExpand;
              });
              if (willExpand && !_checklists.containsKey(apartment.id)) {
                _fetchChecklist(apartment.id);
              }
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

                  // Start-cleaning parking pass check
                  _buildStartChecklistDisplay(apartment.id),

                  // Finish-cleaning checklist (towels, code, parking, water)
                  _buildChecklistDisplay(apartment.id),

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

  Widget _buildCalculatorSection() {
    return Card(
      margin: const EdgeInsets.only(top: 8.0, bottom: 24.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      color: Colors.white,
      child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8CB2A4).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.cleaning_services, color: Color(0xFF8CB2A4), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Cleanings Calculator',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final initialRange = _selectedDateRange ??
                      DateTimeRange(
                        start: DateTime(DateTime.now().year, DateTime.now().month, 1),
                        end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                      );
                  final range = await showDialog<DateTimeRange>(
                    context: context,
                    builder: (context) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Color(0xFF8CB2A4),
                            onPrimary: Colors.white,
                            onSurface: Color(0xFF2C3E50),
                          ),
                        ),
                        child: Dialog(
                          insetPadding: const EdgeInsets.all(16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 500,
                              width: 400,
                              child: DateRangePickerDialog(
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                                initialDateRange: initialRange,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                  if (range != null) {
                    setState(() {
                      _selectedDateRange = range;
                    });
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.date_range, color: Color(0xFF8CB2A4), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedDateRange == null
                              ? 'Select Date Range'
                              : "${DateFormat('MMM d, yyyy').format(_selectedDateRange!.start)} - ${DateFormat('MMM d, yyyy').format(_selectedDateRange!.end)}",
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_selectedDateRange != null) ...[
                const SizedBox(height: 20),
                _buildCalculatorResults(),
              ],
            ],
        ),
      ),
    );
  }

  Widget _buildCalculatorResults() {
    if (_calendars.isEmpty && _apartments.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8CB2A4))),
      );
    }

    final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
    final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59);

    int totalApartmentCleanings = 0;
    int totalRoomsCleaned = 0;
    
    final apartmentWidgets = _apartments.map((apt) {
      int cleanings = 0;

      for (final cal in _calendars) {
        for (final ev in cal.events) {
          if (ev.isBlocked) continue;
          if (!_isRoomMatched(ev.room, apt.name)) continue;

          final evEnd = DateTime(ev.end.year, ev.end.month, ev.end.day);
          if (!evEnd.isBefore(start) && evEnd.isBefore(end)) {
            cleanings++;
          }
        }
      }
      
      bool isKirwansLane = apt.name.toLowerCase().contains('kirwans lane');
      bool isRoom = apt.name.toLowerCase().contains('room');

      if (isRoom && !isKirwansLane) {
        totalRoomsCleaned += cleanings;
      } else {
        totalApartmentCleanings += cleanings;
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                apt.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF8CB2A4).withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF8CB2A4)),
                  const SizedBox(width: 4),
                  Text(
                    '$cleanings',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8CB2A4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();

>>>>>>> Stashed changes
    return Column(
      children: [
        const Text(
          'Todays Rating',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final ratingValue = index + 1;
            return IconButton(
              icon: Icon(
                (_ratings[apartmentId] ?? 0) >= ratingValue
                    ? Icons.star
                    : Icons.star_border,
                color: Colors.amber,
                size: 32,
              ),
              onPressed: () => _updateRating(apartmentId, ratingValue),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cleaning', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF8CB2A4),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined, color: Colors.white),
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
      body: _isFetchingInitialData
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _initializeStatuses,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 8.0,
                ),
                itemCount: _apartments.length,
                itemBuilder: (context, index) {
                  final apartment = _apartments[index];
                  final String status =
                      _cleaningStatus[apartment.id] ?? 'not_cleaned';
                  final bool isLoading = _isLoading[apartment.id] ?? false;
                  final int rating = _ratings[apartment.id] ?? 0;

                  String buttonText;
                  Color buttonColor;
                  VoidCallback? onPressedAction;
                  bool isButtonDisabled =
                      isLoading || (status == 'not_cleaned' && rating == 0);

                  switch (status) {
                    case 'in_progress':
                      buttonText = 'Finish Cleaning';
                      buttonColor = const Color(0xFFE57373);
                      onPressedAction =
                          () => _updateStatus(apartment.id, 'stop');
                      break;
                    case 'cleaned':
                      buttonText = 'Resume Cleaning';
                      buttonColor = const Color(0xFFF7C59F);
                      onPressedAction =
                          () => _updateStatus(apartment.id, 'start');
                      break;
                    default:
                      buttonText = 'Start Cleaning';
                      buttonColor = const Color(0xFF8CB2A4);
                      onPressedAction =
                          () => _showCleaningTimePicker(apartment.id);
                  }

                  return Card(
                    color: Colors.white,
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Spacer(),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  apartment.name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: (status != 'not_cleaned') && !isLoading
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.refresh,
                                          color: Colors.blueGrey,
                                        ),
                                        onPressed: () =>
                                            _showResetConfirmation(apartment),
                                      )
                                    : const SizedBox(width: 48),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: apartment.imageUrl.isNotEmpty
                                ? NetworkImage(apartment.imageUrl)
                                : null,
                            child: apartment.imageUrl.isEmpty
                                ? const Icon(
                                    Icons.apartment,
                                    size: 50,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _buildStarRating(apartment.id),
                          const SizedBox(height: 16),
                          isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : SizedBox(
                                  width: 220,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed:
                                        isButtonDisabled ? null : onPressedAction,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: buttonColor,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          Colors.grey.shade400,
                                      textStyle: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(buttonText),
                                  ),
                                ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}