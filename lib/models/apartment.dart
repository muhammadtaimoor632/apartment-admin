class Apartment {
  final String id;
  final String name;
  final String imageUrl; // ADDED

  Apartment({
    required this.id,
    required this.name,
    this.imageUrl = '', // ADDED
  });
}