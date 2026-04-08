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
        title: Row(
          children: [
            const Expanded(
              child: Text(
                'Inventory',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.help_outline, color: Colors.white),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => const _GlobalInventoryNotesDialog(),
                );
              },
            ),
          ],
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

// ─────────────────────────────────────────────────────────────────────────────
//  Global Inventory Notes Popup Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _GlobalInventoryNotesDialog extends StatefulWidget {
  const _GlobalInventoryNotesDialog();

  @override
  State<_GlobalInventoryNotesDialog> createState() =>
      _GlobalInventoryNotesDialogState();
}

class _GlobalInventoryNotesDialogState
    extends State<_GlobalInventoryNotesDialog> {
  // We'll reuse the "Admin|GlobalNote" key, or a specific "Admin|InventoryNote".
  // Using Admin|GlobalNote keeps it synced with the Today page notes.
  // We can use ApiService.fetchAdminNote and saveAdminNote.

  bool _loading = true;
  bool _saving = false;
  final _ctrl = TextEditingController();

  static const _primaryDark = Color(0xFF5D8A7A);

  @override
  void initState() {
    super.initState();
    ApiService.fetchAdminNote().then((noteStr) {
      if (mounted) {
        setState(() {
          _ctrl.text = noteStr;
          _loading = false;
        });
      }
    });
  }

  Future<void> _saveNotes() async {
    setState(() => _saving = true);
    final ok = await ApiService.saveAdminNote(_ctrl.text);
    if (mounted) {
      setState(() => _saving = false);
      if (ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notes saved successfully'),
            backgroundColor: _primaryDark,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save notes'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.note_alt_outlined, color: _primaryDark),
                const SizedBox(width: 8),
                const Text(
                  'Global Notes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3E3A),
                  ),
                ),
                const Spacer(),
                if (_saving)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _primaryDark,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const SizedBox(
                height: 150,
                child: Center(
                  child: CircularProgressIndicator(color: _primaryDark),
                ),
              )
            else
              Container(
                height: 200,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    hintText: 'Add global notes here...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading || _saving ? null : _saveNotes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Save Notes',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
