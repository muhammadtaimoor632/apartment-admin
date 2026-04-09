import 'package:flutter/material.dart';
import 'package:wild_atlantic_hub/models/inventory_item.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';
import 'package:wild_atlantic_hub/services/scraper_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Brand colours (shared internally)
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const primary = Color(0xFF8CB2A4);
  static const primaryDark = Color(0xFF5D8A7A);
  static const primaryLight = Color(0xFFB8D4CC);
  static const bg = Color(0xFFF4F7F6);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Widget
// ─────────────────────────────────────────────────────────────────────────────
class ApartmentInventoryListPage extends StatefulWidget {
  final String apartmentId;
  final String apartmentName;

  const ApartmentInventoryListPage({
    super.key,
    required this.apartmentId,
    required this.apartmentName,
  });

  @override
  State<ApartmentInventoryListPage> createState() =>
      _ApartmentInventoryListPageState();
}

class _ApartmentInventoryListPageState
    extends State<ApartmentInventoryListPage> {
  bool _isLoading = true;
  List<InventoryItem> _inventoryItems = [];
  final Map<int, bool> _isUpdatingStock = {};
  final Map<int, bool> _isScraping = {};

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  void _sortItems() {
    _inventoryItems.sort((a, b) {
      final stockA = a.stock[widget.apartmentId] ?? 0;
      final stockB = b.stock[widget.apartmentId] ?? 0;

      if (stockA != stockB) {
        return stockA.compareTo(stockB);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  Future<void> _loadInventory() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final allItems = await ApiService.fetchInventoryForApartment(
        widget.apartmentId,
      );
      if (mounted) {
        setState(() {
          _inventoryItems = allItems;
          _sortItems();
        });
        _scrapeMissingImages();
      }
    } catch (e) {
      if (mounted) _showSnackBar('An error occurred: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _scrapeMissingImages({InventoryItem? singleItem}) async {
    final itemsToScrape = singleItem != null ? [singleItem] : _inventoryItems;
    for (final item in itemsToScrape) {
      if (item.imageUrl.isEmpty && item.url.isNotEmpty) {
        if (!mounted) continue;
        setState(() => _isScraping[item.id] = true);
        final scrapedUrl = await ScraperService.scrapeImageUrl(item.url);
        if (scrapedUrl != null && scrapedUrl.isNotEmpty) {
          try {
            final response = await ApiService.updateImageUrl(
              item.id,
              scrapedUrl,
            );
            if (response.statusCode == 200 && mounted) {
              setState(() => item.imageUrl = scrapedUrl);
            }
          } catch (_) {}
        }
        if (mounted) setState(() => _isScraping.remove(item.id));
      }
    }
  }

  Future<void> _updateStock(InventoryItem item, String action) async {
    if (!mounted) return;

    int currentStock = item.stock[widget.apartmentId] ?? 0;
    int newStock = currentStock;
    if (action == 'increment')
      newStock++;
    else if (action == 'decrement' && currentStock > 0)
      newStock--;

    if (newStock == currentStock) return;

    setState(() => _isUpdatingStock[item.id] = true);
    try {
      final response = await ApiService.updateStock(item.id, newStock);
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            item.stock[widget.apartmentId] = newStock;
            _sortItems();
          });
        }
      } else {
        if (mounted)
          _showSnackBar(
            'Failed to update stock: ${response.reasonPhrase}',
            isError: true,
          );
      }
    } catch (e) {
      if (mounted) _showSnackBar('An error occurred: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUpdatingStock.remove(item.id));
    }
  }

  // _updateStock is above

  void _deleteItem(InventoryItem item) async {
    final int originalIndex = _inventoryItems.indexOf(item);
    setState(() => _inventoryItems.remove(item));
    try {
      final response = await ApiService.deleteItem(item.id);
      if (response.statusCode != 200) throw Exception('Server error');
      if (mounted)
        _showSnackBar('"${item.name}" deleted successfully.', isError: false);
    } catch (_) {
      if (mounted) {
        setState(() => _inventoryItems.insert(originalIndex, item));
        _showSnackBar(
          'Failed to delete "${item.name}". Please try again.',
          isError: true,
        );
      }
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : _C.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Builders ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        title: Text(
          widget.apartmentName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: _C.primaryDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _C.primary));
    }
    if (_inventoryItems.isEmpty) {
      return RefreshIndicator(
        color: _C.primary,
        onRefresh: _loadInventory,
        child: Stack(
          children: [
            ListView(),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _C.primaryLight.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      size: 56,
                      color: _C.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'No inventory items yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3E3A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the button below to add your first item.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _C.primary,
      onRefresh: _loadInventory,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _inventoryItems.length,
        itemBuilder: (context, index) {
          final item = _inventoryItems[index];
          return _buildDismissible(item);
        },
      ),
    );
  }

  Widget _buildDismissible(InventoryItem item) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent.shade200,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 22),
      ),
      confirmDismiss: (_) async {
        return await _confirmDelete(item.name);
      },
      onDismissed: (_) => _deleteItem(item),
      child: _InventoryItemCard(
        item: item,
        apartmentId: widget.apartmentId,
        isScraping: _isScraping[item.id] ?? false,
        isUpdating: _isUpdatingStock[item.id] ?? false,
        onIncrement: () => _updateStock(item, 'increment'),
        onDecrement: () => _updateStock(item, 'decrement'),
      ),
    );
  }

  Future<bool?> _confirmDelete(String itemName) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_rounded,
                  color: Colors.red.shade400,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Delete Item',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Are you sure you want to delete "$itemName"? This cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Inventory item card (compact list row)
// ─────────────────────────────────────────────────────────────────────────────
class _InventoryItemCard extends StatelessWidget {
  final InventoryItem item;
  final String apartmentId;
  final bool isScraping;
  final bool isUpdating;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _InventoryItemCard({
    required this.item,
    required this.apartmentId,
    required this.isScraping,
    required this.isUpdating,
    required this.onIncrement,
    required this.onDecrement,
  });

  int get _stock => item.stock[apartmentId] ?? 0;

  Color get _stockColor {
    if (_stock == 0) return Colors.red.shade400;
    if (_stock == 1) return Colors.deepOrange.shade600;
    if (_stock == 2) return Colors.orange.shade500;
    return _C.primaryDark;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Small thumbnail
              _buildImage(),
              const SizedBox(width: 12),
              // Name + stock label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF2D3E3A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _stockLabel(),
                      style: TextStyle(
                        fontSize: 11,
                        color: _stockColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Stock controls
              if (isUpdating)
                const SizedBox(
                  width: 80,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _C.primary,
                      ),
                    ),
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _controlButton(
                      Icons.remove_rounded,
                      onDecrement,
                      _stock == 0 ? Colors.grey.shade200 : _C.primaryLight,
                      _stock == 0 ? Colors.grey : _C.primaryDark,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '$_stock',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _stockColor,
                        ),
                      ),
                    ),
                    _controlButton(
                      Icons.add_rounded,
                      onIncrement,
                      _C.primaryLight,
                      _C.primaryDark,
                    ),
                  ],
                ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: Colors.grey.shade100,
          indent: 16,
          endIndent: 16,
        ),
      ],
    );
  }

  Widget _buildImage() {
    final radius = BorderRadius.circular(8);
    if (isScraping) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _C.primaryLight.withValues(alpha: 0.3),
          borderRadius: radius,
        ),
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _C.primary),
          ),
        ),
      );
    }
    if (item.imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          item.imageUrl,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(radius),
        ),
      );
    }
    return _placeholder(radius);
  }

  Widget _placeholder(BorderRadius radius) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFDCEDE8),
        borderRadius: radius,
      ),
      child: const Icon(
        Icons.shopping_basket_outlined,
        color: _C.primary,
        size: 22,
      ),
    );
  }

  String _stockLabel() {
    if (_stock == 0) return 'Out of Stock';
    if (_stock == 1) return 'Almost out';
    if (_stock == 2) return 'Low Stock';
    return 'In Stock';
  }

  Widget _controlButton(
    IconData icon,
    VoidCallback onPressed,
    Color bg,
    Color fg,
  ) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: fg, size: 16),
      ),
    );
  }
}
