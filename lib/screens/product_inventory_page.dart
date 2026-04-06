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
  static const Color _primaryLight = Color(0xFFB8D4CC);
  static const Color _accent = Color(0xFF4A7C6F);

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
      body: FutureBuilder<(List<CleaningDetails>, Map<String, int>)>(
        future: _dataFuture,
        builder: (context, snapshot) {
          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              _buildSliverAppBar(context, innerBoxIsScrolled),
            ],
            body: _buildBody(snapshot),
          );
        },
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, bool innerBoxIsScrolled) {
    return SliverAppBar(
      expandedHeight: 160,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: _primaryDark,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Inventory',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'Select an apartment',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_accent, _primary, _primaryLight],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              Positioned(
                right: 40,
                bottom: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Positioned(
                left: -20,
                bottom: 0,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
      AsyncSnapshot<(List<CleaningDetails>, Map<String, int>)> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(color: _primary),
      );
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
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.82,
        ),
        itemCount: apartments.length,
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: _primary.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Image strip ──────────────────────────────────────────
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    apartment.imageUrl.isNotEmpty
                        ? Image.network(
                            apartment.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _placeholderBg(),
                          )
                        : _placeholderBg(),
                    // subtle gradient overlay so text is readable
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.3),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // item count badge
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _primaryDark.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$inventoryCount item${inventoryCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Info row ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        apartment.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF2D3E3A),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: _primaryDark,
                      ),
                    ),
                  ],
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
      child: const Icon(Icons.apartment_rounded,
          color: Color(0xFF8CB2A4), size: 56),
    );
  }
}
