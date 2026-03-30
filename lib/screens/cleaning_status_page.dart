import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  
  // New State maps
  final Map<String, String> _lastRatedAts = {};
  final Map<String, TextEditingController> _remarksControllers = {};
  final Map<String, File?> _selectedImages = {};
  final Map<String, String> _existingImageUrls = {};
  final Map<String, String> _startTimes = {};
  final Map<String, String> _endTimes = {};
  
  bool _isFetchingInitialData = true;

  @override
  void initState() {
    super.initState();
    _initializeStatuses();
  }

  @override
  void dispose() {
    for (var controller in _remarksControllers.values) {
      controller.dispose();
    }
    super.dispose();
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
            _lastRatedAts[detail.id] = detail.lastRatedAt;
            _existingImageUrls[detail.id] = detail.cleaningImageUrl;
            _startTimes[detail.id] = detail.startTime;
            _endTimes[detail.id] = detail.endTime;
            
            if (!_remarksControllers.containsKey(detail.id)) {
              _remarksControllers[detail.id] = TextEditingController(text: detail.remarks);
            } else {
              _remarksControllers[detail.id]!.text = detail.remarks;
            }
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

  Future<void> _pickImage(String apartmentId) async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (pickedFile != null) {
        setState(() {
          _selectedImages[apartmentId] = File(pickedFile.path);
        });
      }
    } catch (e) {
      _showSnackBar('Failed to pick image.', Colors.red);
    }
  }

  Future<void> _saveFeedback(String apartmentId) async {
    if (!mounted) return;
    setState(() {
      _isLoading[apartmentId] = true;
    });

    try {
      String? base64Image;
      if (_selectedImages[apartmentId] != null) {
        final bytes = await _selectedImages[apartmentId]!.readAsBytes();
        base64Image = base64Encode(bytes);
      }
      
      final remarks = _remarksControllers[apartmentId]?.text ?? '';

      final response = await ApiService.updateCleaningFeedback(
        apartmentId: apartmentId,
        remarks: remarks,
        base64Image: base64Image,
      );

      if (response.statusCode == 200) {
        _showSnackBar('Feedback saved successfully!', Colors.green);
        setState(() {
            _selectedImages[apartmentId] = null;
        });
      } else {
        final responseBody = json.decode(response.body);
        final errorMessage = responseBody['message'] ?? 'An unknown error occurred.';
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

  Widget _buildStarRating(String apartmentId) {
    final lastRated = _lastRatedAts[apartmentId];
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
        if (lastRated != null && lastRated.isNotEmpty && lastRated != 'Unknown')
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              'Last rated: $lastRated',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
      ],
    );
  }

  Widget _buildFeedbackSection(String apartmentId) {
     return Column(
       crossAxisAlignment: CrossAxisAlignment.stretch,
       children: [
         const SizedBox(height: 16),
         const Text(
           'Condition Remarks',
           style: TextStyle(
             fontSize: 14,
             fontWeight: FontWeight.w600,
             color: Colors.black54,
           ),
         ),
         const SizedBox(height: 8),
         TextField(
           controller: _remarksControllers[apartmentId],
           maxLines: 2,
           decoration: InputDecoration(
             hintText: 'Add remarks on room cleanliness...',
             hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
             border: OutlineInputBorder(
               borderRadius: BorderRadius.circular(10),
               borderSide: BorderSide(color: Colors.grey.shade300),
             ),
             enabledBorder: OutlineInputBorder(
               borderRadius: BorderRadius.circular(10),
               borderSide: BorderSide(color: Colors.grey.shade300),
             ),
             contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
           ),
         ),
         const SizedBox(height: 12),
         Row(
           children: [
             Expanded(
               child: OutlinedButton.icon(
                 onPressed: () => _pickImage(apartmentId),
                 icon: const Icon(Icons.camera_alt_outlined, size: 18),
                 label: const Text('Add Photo', style: TextStyle(fontSize: 13)),
                 style: OutlinedButton.styleFrom(
                   foregroundColor: Colors.blueGrey,
                   side: const BorderSide(color: Colors.blueGrey),
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                 ),
               ),
             ),
             const SizedBox(width: 8),
             Expanded(
               child: ElevatedButton(
                 onPressed: _isLoading[apartmentId] == true ? null : () => _saveFeedback(apartmentId),
                 style: ElevatedButton.styleFrom(
                   backgroundColor: const Color(0xFF8CB2A4),
                   foregroundColor: Colors.white,
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                 ),
                 child: const Text('Save Feedback', style: TextStyle(fontSize: 13)),
               ),
             ),
           ],
         ),
         if (_selectedImages[apartmentId] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.image, size: 16, color: Colors.green),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text('Image selected to upload', style: TextStyle(fontSize: 12, color: Colors.green)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      setState(() {
                         _selectedImages[apartmentId] = null;
                      });
                    },
                  )
                ],
              ),
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
                          const SizedBox(height: 12),
                          Text(
                            'Started: ${_startTimes[apartment.id] ?? 'N/A'}',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              'Finished: ${_endTimes[apartment.id] ?? 'N/A'}',
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            ),
                          ),
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
                          _buildFeedbackSection(apartment.id),
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