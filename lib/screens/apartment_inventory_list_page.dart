import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wild_atlantic_hub/models/inventory_item.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';
import 'package:wild_atlantic_hub/services/scraper_service.dart';

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

  Future<void> _loadInventory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final allItems = await ApiService.fetchInventoryItems();
      if (mounted) {
        setState(() {
          // NEW: Filter items to only include those that have a stock entry for the current apartment.
          _inventoryItems = allItems
              .where((item) => item.stock.containsKey(widget.apartmentId))
              .toList();

          _inventoryItems.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        });
        _scrapeMissingImages();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _scrapeMissingImages({InventoryItem? singleItem}) async {
    final itemsToScrape = singleItem != null ? [singleItem] : _inventoryItems;
    for (final item in itemsToScrape) {
      if (item.imageUrl.isEmpty && item.url.isNotEmpty) {
        if (!mounted) continue;
        setState(() {
          _isScraping[item.id] = true;
        });

        final scrapedUrl = await ScraperService.scrapeImageUrl(item.url);

        if (scrapedUrl != null && scrapedUrl.isNotEmpty) {
          try {
            final response = await ApiService.updateImageUrl(
              item.id,
              scrapedUrl,
            );
            if (response.statusCode == 200 && mounted) {
              setState(() {
                item.imageUrl = scrapedUrl;
              });
            }
          } catch (e) {
            // Silently fail
          }
        }

        if (mounted) {
          setState(() {
            _isScraping.remove(item.id);
          });
        }
      }
    }
  }

  Future<void> _updateStock(InventoryItem item, String action) async {
    if (!mounted) return;
    setState(() {
      _isUpdatingStock[item.id] = true;
    });

    try {
      final response = await ApiService.updateStock(
        item.id,
        action,
        widget.apartmentId,
      );
      if (response.statusCode == 200) {
        final dynamic decodedData = json.decode(response.body);
        final String apartmentId = decodedData['apartmentId'];
        final int newStock = decodedData['new_stock'];

        if (mounted) {
          setState(() {
            item.stock[apartmentId] = newStock;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update stock: ${response.reasonPhrase}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingStock.remove(item.id);
        });
      }
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
        // After adding, reload the inventory to apply the filter
        _loadInventory();
        _scrapeMissingImages(singleItem: newItem);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _deleteItem(InventoryItem item) async {
    final int originalIndex = _inventoryItems.indexOf(item);
    setState(() {
      _inventoryItems.remove(item);
    });

    try {
      final response = await ApiService.deleteItem(item.id);
      if (response.statusCode != 200) {
        throw Exception('Failed to delete on server');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${item.name}" deleted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _inventoryItems.insert(originalIndex, item);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete "${item.name}". Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not launch $urlString')));
      }
    }
  }

  Widget _buildLeadingImage(InventoryItem item) {
    bool isScraping = _isScraping[item.id] ?? false;

    if (isScraping) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (item.imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Image.network(
          item.imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.broken_image_outlined,
            color: Colors.grey,
            size: 40,
          ),
        ),
      );
    }

    return const Icon(
      Icons.shopping_basket_outlined,
      color: Colors.grey,
      size: 40,
    );
  }

  Widget _buildStockController(InventoryItem item) {
    bool isUpdating = _isUpdatingStock[item.id] ?? false;

    if (isUpdating) {
      return const SizedBox(
        width: 96,
        height: 24,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => _updateStock(item, 'decrement'),
          iconSize: 24,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        Text(
          (item.stock[widget.apartmentId] ?? 0).toString(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _updateStock(item, 'increment'),
          iconSize: 24,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.apartmentName,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF8CB2A4),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: showAddItemDialog,
        backgroundColor: const Color(0xFF8CB2A4),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_inventoryItems.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadInventory,
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  'No inventory items found for ${widget.apartmentName}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ),
            ),
            ListView(), // To make RefreshIndicator work
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInventory,
      child: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: _inventoryItems.length,
        itemBuilder: (context, index) {
          final item = _inventoryItems[index];
          return Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            background: Card(
              color: Colors.redAccent,
              margin: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 8.0,
              ),
              child: const Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 20.0),
                  child: Icon(Icons.delete, color: Colors.white),
                ),
              ),
            ),
            confirmDismiss: (direction) async {
              return await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  contentPadding: const EdgeInsets.fromLTRB(30, 0, 30, 24),
                  title: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Center(child: Text('Confirm Deletion')),
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
                    'Are you sure you want to delete "${item.name}"?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (direction) {
              _deleteItem(item);
            },
            child: Card(
              color: Colors.white,
              elevation: 2,
              margin: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 8.0,
              ),
              child: ListTile(
                leading: SizedBox(
                  width: 60,
                  height: 60,
                  child: _buildLeadingImage(item),
                ),
                title: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  item.url,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                trailing: _buildStockController(item),
                onTap: item.url.isNotEmpty ? () => _launchURL(item.url) : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

// Dialog for adding a new item
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
      final result = {
        'name': _nameController.text,
        'url': _urlController.text,
        'stock': int.parse(_stockController.text),
      };
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      contentPadding: const EdgeInsets.fromLTRB(30, 8, 30, 24),
      title: Stack(
        clipBehavior: Clip.none,
        children: [
          const Center(child: Text('Add New Inventory Item')),
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
      content: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Product Name'),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Please enter a name'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'Product URL'),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stockController,
                decoration: const InputDecoration(labelText: 'Initial Stock'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a stock number';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submitForm, child: const Text('Add Item')),
      ],
    );
  }
}
