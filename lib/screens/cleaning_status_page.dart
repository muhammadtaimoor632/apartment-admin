import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:wild_atlantic_hub/models/apartment.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';
import 'package:wild_atlantic_hub/screens/status_details_page.dart';

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
      final detailsList = await ApiService.fetchCleaningDetails();
      if (mounted) {
        setState(() {
          _apartments = detailsList
              .map(
                (d) => Apartment(id: d.id, name: d.name, imageUrl: d.imageUrl),
              )
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Error fetching apartment list. Please try again.',
          Colors.red,
        );
      }
    }

    for (var apt in _apartments) {
      _cleaningStatus[apt.id] = 'not_cleaned';
      _isLoading[apt.id] = false;
      _ratings[apt.id] = 0;
    }
    await _fetchStatusesFromServer();
    if (mounted) {
      setState(() {
        _isFetchingInitialData = false;
      });
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
            onPressed: () => Navigator.pop(context, false),
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
            }
            if (statusToSend == 'stop') {
              _cleaningStatus[apartmentId] = 'cleaned';
            }
            if (statusToSend == 'reset') {
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

  Widget _buildStarRating(String apartmentId) {
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
                _ratings[apartmentId]! >= ratingValue
                    ? Icons.star
                    : Icons.star_border,
                color: Colors.amber,
                size: 32,
              ),
              onPressed: () {
                setState(() {
                  _ratings[apartmentId] = ratingValue;
                });
              },
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
                      onPressedAction = () =>
                          _updateStatus(apartment.id, 'stop');
                      break;
                    case 'cleaned':
                      buttonText = 'Resume Cleaning';
                      buttonColor = const Color(0xFFF7C59F);
                      onPressedAction = () =>
                          _updateStatus(apartment.id, 'start');
                      break;
                    default:
                      buttonText = 'Start Cleaning';
                      buttonColor = const Color(0xFF8CB2A4);
                      onPressedAction = () =>
                          _showCleaningTimePicker(apartment.id);
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
                                    onPressed: isButtonDisabled
                                        ? null
                                        : onPressedAction,
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
