import 'package:flutter/material.dart';
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
    _detailsFuture = _fetchDetails();
  }

  Future<List<CleaningDetails>> _fetchDetails() {
    // No need to call setState here, FutureBuilder will handle it
    _detailsFuture = ApiService.fetchCleaningDetails();
    return _detailsFuture;
  }

  Widget _buildDetailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingStars(int rating) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: List.generate(5, (index) {
        return Icon(
          index < rating ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 20,
        );
      }),
    );
  }

  // Helper to get the correct status icon
  Icon _getStatusIcon(String status) {
    switch (status) {
      case 'Cleaned':
        return const Icon(Icons.check_circle, color: Colors.green, size: 28);
      case 'In Progress':
        return const Icon(Icons.timelapse, color: Colors.orange, size: 28);
      default:
        return const Icon(
          Icons.warning_amber_rounded,
          color: Colors.red,
          size: 28,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Current Status',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF8CB2A4),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDetails,
        child: FutureBuilder<List<CleaningDetails>>(
          future: _detailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No status details available.'));
            }

            final detailsList = snapshot.data!;

            return ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: detailsList.length,
              itemBuilder: (context, index) {
                final details = detailsList[index];
                return Card(
                  color: Colors.white, // Explicitly set card color to white
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    // Use Stack to position the icon
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              details.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Divider(height: 24),
                            _buildDetailRow('Status', details.status),
                            _buildDetailRow('Start Time', details.startTime),
                            _buildDetailRow('End Time', details.endTime),
                            _buildDetailRow('Duration', details.duration),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Rating',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  _buildRatingStars(details.rating),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _getStatusIcon(details.status),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}