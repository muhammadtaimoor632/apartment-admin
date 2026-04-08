import 'package:flutter/material.dart';
import 'package:wild_atlantic_hub/models/cleaning_details.dart';

import 'package:wild_atlantic_hub/services/api_service.dart';
import 'package:wild_atlantic_hub/screens/apartment_inventory_list_page.dart';

class ProductInventoryPage extends StatefulWidget {
  const ProductInventoryPage({super.key});

  @override
  State<ProductInventoryPage> createState() => _ProductInventoryPageState();
}

class _ProductInventoryPageState extends State<ProductInventoryPage> {
  late Future<(List<CleaningDetails>, Map<String, int>)> _dataFuture;

  // Brand colour palette
  static const Color _primary = Color(0xFF8CB2A4);
  static const Color _primaryDark = Color(0xFF5D8A7A);

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchData();
  }

  Future<(List<CleaningDetails>, Map<String, int>)> _fetchData() async {
    final apartments = await ApiService.fetchCleaningDetails();

    // Fetch individual inventory item counts per apartment
    final inventoryCounts = <String, int>{};
    await Future.wait(
      apartments.map((apt) async {
        try {
          final items = await ApiService.fetchInventoryForApartment(apt.id);
          inventoryCounts[apt.id] = items.length;
        } catch (_) {
          inventoryCounts[apt.id] = 0;
        }
      }),
    );

    return (apartments, inventoryCounts);
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
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text(
          'Inventory',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _primaryDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _dataFuture = _fetchData();
            }),
          ),
        ],
      ),
      body: FutureBuilder<(List<CleaningDetails>, Map<String, int>)>(
        future: _dataFuture,
        builder: (context, snapshot) => _buildBody(snapshot),
      ),
    );
  }

  Widget _buildBody(
    AsyncSnapshot<(List<CleaningDetails>, Map<String, int>)> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }
    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(
              'Error: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    if (!snapshot.hasData || snapshot.data!.$1.isEmpty) {
      return const Center(
        child: Text(
          'No apartments found.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final apartments = snapshot.data!.$1;
    final inventoryCounts = snapshot.data!.$2;

    return RefreshIndicator(
      color: _primary,
      onRefresh: () {
        setState(() {
          _dataFuture = _fetchData();
        });
        return _dataFuture;
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        itemCount: apartments.length,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final apartment = apartments[index];
          final inventoryCount = inventoryCounts[apartment.id] ?? 0;
          return _ApartmentInventoryCard(
            apartment: apartment,
            inventoryCount: inventoryCount,
            onTap: () =>
                _navigateToInventoryList(context, apartment.id, apartment.name),
          );
        },
      ),
    );
  }
}

class _ApartmentInventoryCard extends StatelessWidget {
  final CleaningDetails apartment;
  final int inventoryCount;
  final VoidCallback onTap;

  static const Color _primary = Color(0xFF8CB2A4);
  static const Color _primaryDark = Color(0xFF5D8A7A);

  const _ApartmentInventoryCard({
    required this.apartment,
    required this.inventoryCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: _primary.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Row(
            children: [
              // ── Image ──────────────────────────────────────────
              SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    apartment.imageUrl.isNotEmpty
                        ? Image.network(
                            apartment.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholderBg(),
                          )
                        : _placeholderBg(),
                  ],
                ),
              ),

              // ── Info column ─────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        apartment.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF2D3E3A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$inventoryCount item${inventoryCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: _primaryDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Arrow ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: _primaryDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderBg() {
    return Container(
      color: const Color(0xFFDCEDE8),
      child: const Icon(
        Icons.apartment_rounded,
        color: Color(0xFF8CB2A4),
        size: 56,
      ),
    );
  }
}
