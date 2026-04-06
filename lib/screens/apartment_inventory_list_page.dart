import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
  static const accent = Color(0xFF4A7C6F);
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

  // ── Data loading ────────────────────────────────────────────────────────────
  Future<void> _loadInventory() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final allItems = await ApiService.fetchInventoryItems();
      if (mounted) {
        setState(() {
          _inventoryItems = allItems
              .where((item) => item.stock.containsKey(widget.apartmentId))
              .toList()
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
    final itemsToScrape =
        singleItem != null ? [singleItem] : _inventoryItems;
    for (final item in itemsToScrape) {
      if (item.imageUrl.isEmpty && item.url.isNotEmpty) {
        if (!mounted) continue;
        setState(() => _isScraping[item.id] = true);
        final scrapedUrl = await ScraperService.scrapeImageUrl(item.url);
        if (scrapedUrl != null && scrapedUrl.isNotEmpty) {
          try {
            final response =
                await ApiService.updateImageUrl(item.id, scrapedUrl);
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
    setState(() => _isUpdatingStock[item.id] = true);
    try {
      final response =
          await ApiService.updateStock(item.id, action, widget.apartmentId);
      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        final String aptId = decoded['apartmentId'];
        final int newStock = decoded['new_stock'];
        if (mounted) setState(() => item.stock[aptId] = newStock);
      } else {
        if (mounted)
          _showSnackBar('Failed to update stock: ${response.reasonPhrase}',
              isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('An error occurred: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUpdatingStock.remove(item.id));
    }
  }

  Future<void> showAddItemDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const AddItemDialog(),
    );
    if (result != null && mounted) {
      try {
        final newItem = await ApiService.addItem(
          name: result['name'],
          url: result['url'],
          stock: result['stock'],
          apartmentId: widget.apartmentId,
        );
        _loadInventory();
        _scrapeMissingImages(singleItem: newItem);
      } catch (e) {
        if (mounted)
          _showSnackBar('Error: ${e.toString()}', isError: true);
      }
    }
  }

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
            isError: true);
      }
    }
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      if (mounted)
        _showSnackBar('Could not launch $urlString', isError: true);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : _C.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Builders ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [_buildSliverAppBar()],
        body: _buildBody(),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      floating: false,
      elevation: 0,
      backgroundColor: _C.primaryDark,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.apartmentName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
            const Text(
              'Inventory',
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
              colors: [_C.accent, _C.primary, _C.primaryLight],
            ),
          ),
          child: Stack(children: [
            Positioned(
              right: -40,
              top: -40,
              child: _circle(200, 0.07),
            ),
            Positioned(
              right: 60,
              bottom: -30,
              child: _circle(110, 0.05),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _circle(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: opacity),
        ),
      );

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: showAddItemDialog,
      backgroundColor: _C.primaryDark,
      foregroundColor: Colors.white,
      elevation: 4,
      icon: const Icon(Icons.add_rounded),
      label: const Text(
        'Add Item',
        style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _C.primary));
    }
    if (_inventoryItems.isEmpty) {
      return RefreshIndicator(
        color: _C.primary,
        onRefresh: _loadInventory,
        child: Stack(children: [
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
                  child: const Icon(Icons.inventory_2_outlined,
                      size: 56, color: _C.primary),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No inventory items yet',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3E3A)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the button below to add your first item.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      color: _C.primary,
      onRefresh: _loadInventory,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.redAccent.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_rounded, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text('Delete',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
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
        onTap: item.url.isNotEmpty ? () => _launchURL(item.url) : null,
      ),
    );
  }

  Future<bool?> _confirmDelete(String itemName) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                child: Icon(Icons.delete_rounded,
                    color: Colors.red.shade400, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Delete Item',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side:
                            BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Delete',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
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
//  Inventory item card
// ─────────────────────────────────────────────────────────────────────────────
class _InventoryItemCard extends StatelessWidget {
  final InventoryItem item;
  final String apartmentId;
  final bool isScraping;
  final bool isUpdating;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback? onTap;

  const _InventoryItemCard({
    required this.item,
    required this.apartmentId,
    required this.isScraping,
    required this.isUpdating,
    required this.onIncrement,
    required this.onDecrement,
    this.onTap,
  });

  int get _stock => item.stock[apartmentId] ?? 0;

  Color get _stockColor {
    if (_stock == 0) return Colors.red.shade400;
    if (_stock <= 2) return Colors.orange.shade600;
    return _C.primaryDark;
  }

  String get _stockLabel {
    if (_stock == 0) return 'Out of Stock';
    if (_stock <= 2) return 'Low Stock';
    return 'In Stock';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _C.primary.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildImage(),
                const SizedBox(width: 14),
                Expanded(child: _buildInfo()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    final radius = BorderRadius.circular(14);

    if (isScraping) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: _C.primaryLight.withValues(alpha: 0.3),
          borderRadius: radius,
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: _C.primary),
          ),
        ),
      );
    }

    if (item.imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          item.imageUrl,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imagePlaceholder(radius),
        ),
      );
    }

    return _imagePlaceholder(radius);
  }

  Widget _imagePlaceholder(BorderRadius radius) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFFDCEDE8),
        borderRadius: radius,
      ),
      child: const Icon(Icons.shopping_basket_outlined,
          color: _C.primary, size: 36),
    );
  }

  Widget _buildInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name + stock status badge
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF2D3E3A),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _stockColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _stockLabel,
                style: TextStyle(
                  color: _stockColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // URL
        if (item.url.isNotEmpty)
          Row(
            children: [
              const Icon(Icons.link_rounded,
                  size: 13, color: _C.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item.url,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _C.primary,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        // Stock controller
        _buildStockController(),
      ],
    );
  }

  Widget _buildStockController() {
    if (isUpdating) {
      return const SizedBox(
        height: 36,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: _C.primary),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _controlButton(
          icon: Icons.remove_rounded,
          onPressed: onDecrement,
          color: _stock == 0 ? Colors.grey.shade300 : _C.primaryLight,
          iconColor: _stock == 0 ? Colors.grey : _C.primaryDark,
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _stockColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$_stock',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _stockColor,
            ),
          ),
        ),
        _controlButton(
          icon: Icons.add_rounded,
          onPressed: onIncrement,
          color: _C.primaryLight,
          iconColor: _C.primaryDark,
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    required Color iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, color: iconColor, size: 18),
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Add Item Dialog
// ─────────────────────────────────────────────────────────────────────────────
class AddItemDialog extends StatefulWidget {
  const AddItemDialog({super.key});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _stockController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _urlController = TextEditingController();
    _stockController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop({
        'name': _nameController.text,
        'url': _urlController.text,
        'stock': int.parse(_stockController.text),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _C.primaryLight.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add_shopping_cart_rounded,
                      color: _C.primaryDark, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Add New Item',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 18, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            // Form
            Form(
              key: _formKey,
              child: Column(
                children: [
                  _styledField(
                    controller: _nameController,
                    label: 'Product Name',
                    hint: 'e.g. Towels',
                    icon: Icons.label_outline_rounded,
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Please enter a name'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                    controller: _urlController,
                    label: 'Product URL',
                    hint: 'https://...',
                    icon: Icons.link_rounded,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                    controller: _stockController,
                    label: 'Initial Stock',
                    hint: '0',
                    icon: Icons.inventory_2_outlined,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return 'Please enter a stock number';
                      if (int.tryParse(v) == null)
                        return 'Please enter a valid number';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.primaryDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Add Item',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _styledField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _C.primary, size: 20),
        filled: true,
        fillColor: const Color(0xFFF4F7F6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: _C.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        labelStyle:
            TextStyle(color: Colors.grey.shade600, fontSize: 14),
      ),
    );
  }
}
