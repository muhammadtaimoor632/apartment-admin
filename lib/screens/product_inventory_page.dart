import 'package:flutter/material.dart';
import 'package:wild_atlantic_hub/models/cleaning_details.dart';
import 'package:wild_atlantic_hub/models/inventory_item.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';
import 'package:wild_atlantic_hub/screens/apartment_inventory_list_page.dart';

class ProductInventoryPage extends StatefulWidget {
  const ProductInventoryPage({super.key});

  @override
  State<ProductInventoryPage> createState() => _ProductInventoryPageState();
}

class _ProductInventoryPageState extends State<ProductInventoryPage> {
  late Future<(List<CleaningDetails>, List<InventoryItem>)> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchData();
  }

  Future<(List<CleaningDetails>, List<InventoryItem>)> _fetchData() async {
    // Use Future.wait to fetch both lists in parallel for efficiency
    final results = await Future.wait([
      ApiService.fetchCleaningDetails(),
      ApiService.fetchInventoryItems(),
    ]);
    return (
      results[0] as List<CleaningDetails>,
      results[1] as List<InventoryItem>,
    );
  }

  void _navigateToInventoryList(
    BuildContext context,
    String apartmentId,
    String apartmentName,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ApartmentInventoryListPage(
          apartmentId: apartmentId,
          apartmentName: apartmentName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF8CB2A4),
      ),
      body: FutureBuilder<(List<CleaningDetails>, List<InventoryItem>)>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.$1.isEmpty) {
            return const Center(child: Text('No apartments found.'));
          }

          final apartments = snapshot.data!.$1;
          final allInventoryItems = snapshot.data!.$2;

          return RefreshIndicator(
            onRefresh: () {
              setState(() {
                _dataFuture = _fetchData();
              });
              return _dataFuture;
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: apartments.length,
              itemBuilder: (context, index) {
                final apartment = apartments[index];
                // NEW: Count only the items that have a stock record for this specific apartment.
                final inventoryCount = allInventoryItems
                    .where((item) => item.stock.containsKey(apartment.id))
                    .length;
                final subtitle =
                    '$inventoryCount ${inventoryCount == 1 ? "item" : "items"}';

                return GestureDetector(
                  onTap: () => _navigateToInventoryList(
                    context,
                    apartment.id,
                    apartment.name,
                  ),
                  child: Card(
                    color: Colors.white,
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24.0,
                        horizontal: 16.0,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 65,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: apartment.imageUrl.isNotEmpty
                                ? NetworkImage(apartment.imageUrl)
                                : null,
                            child: apartment.imageUrl.isEmpty
                                ? const Icon(
                                    Icons.apartment,
                                    color: Colors.grey,
                                    size: 70,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                apartment.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.grey.shade500,
                                size: 18,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}