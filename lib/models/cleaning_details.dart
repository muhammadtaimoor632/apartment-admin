class CleaningDetails {
  final String id;
  final String name;
  final String status;
  final String startTime;
  final String endTime;
  final String duration;
  final int rating;
  final String imageUrl; // ADDED
  final String lastRatedAt; // ADDED
  final String remarks; // ADDED
  final String cleaningImageUrl; // ADDED

  CleaningDetails({
    required this.id,
    required this.name,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.rating,
    required this.imageUrl, // ADDED
    required this.lastRatedAt, // ADDED
    required this.remarks, // ADDED
    required this.cleaningImageUrl, // ADDED
  });

  factory CleaningDetails.fromJson(Map<String, dynamic> json) {
    return CleaningDetails(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Apartment',
      status: json['status'] ?? 'N/A',
      startTime: json['startTime'] ?? 'N/A',
      endTime: json['endTime'] ?? 'N/A',
      duration: json['duration'] ?? 'N/A',
      rating: json['rating'] ?? 0,
      imageUrl: json['imageUrl'] ?? '', // ADDED
      lastRatedAt: json['lastRatedAt'] ?? 'Unknown', // ADDED
      remarks: json['remarks'] ?? '', // ADDED
      cleaningImageUrl: json['cleaningImageUrl'] ?? '', // ADDED
    );
  }
}
