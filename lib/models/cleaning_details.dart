class RatingHistoryEntry {
  final int rating;
  final String date;
  final String remarks;
  final String? imageUrl;

  RatingHistoryEntry({
    required this.rating,
    required this.date,
    required this.remarks,
    this.imageUrl,
  });

  factory RatingHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RatingHistoryEntry(
      rating: json['rating'] ?? 0,
      date: json['date'] ?? '',
      remarks: json['remarks'] ?? '',
      imageUrl: json['image_url'] ?? json['imageUrl'] ?? json['image'],
    );
  }
}

class CleaningDetails {
  final String id;
  final String name;
  final String status;
  final String startTime;
  final String endTime;
  final String duration;
  final int rating;
  final String imageUrl;
  final String lastRatedAt;
  final String remarks;
  final String cleaningImageUrl;
  final List<RatingHistoryEntry> ratingHistory;

  CleaningDetails({
    required this.id,
    required this.name,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.rating,
    required this.imageUrl,
    required this.lastRatedAt,
    required this.remarks,
    required this.cleaningImageUrl,
    required this.ratingHistory,
  });

  factory CleaningDetails.fromJson(Map<String, dynamic> json) {
    List<RatingHistoryEntry> history = [];
    final historyList = json['ratingHistory'] ?? json['rating_history'];
    if (historyList != null && historyList is List) {
      history = historyList
          .map((entry) => RatingHistoryEntry.fromJson(entry as Map<String, dynamic>))
          .toList();
    }

    return CleaningDetails(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Apartment',
      status: json['status'] ?? 'N/A',
      startTime: json['startTime'] ?? 'N/A',
      endTime: json['endTime'] ?? 'N/A',
      duration: json['duration'] ?? 'N/A',
      rating: json['rating'] ?? 0,
      imageUrl: json['imageUrl'] ?? '',
      lastRatedAt: json['lastRatedAt'] ?? 'Unknown',
      remarks: json['remarks'] ?? '',
      cleaningImageUrl: json['cleaningImageUrl'] ?? '',
      ratingHistory: history,
    );
  }
}
