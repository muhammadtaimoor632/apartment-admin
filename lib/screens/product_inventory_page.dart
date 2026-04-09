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
  String _currentNote = '';

  // Brand colour palette
  static const Color _primary = Color(0xFF8CB2A4);
  static const Color _primaryDark = Color(0xFF5D8A7A);

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchData();
    _fetchNote();
  }

  Future<void> _fetchNote() async {
    final note = await ApiService.fetchGlobalInventoryNote();
    if (mounted) {
      setState(() {
        _currentNote = note;
      });
    }
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
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.help_outline, color: Colors.white),
          onPressed: () async {
            await showDialog(
              context: context,
              builder: (ctx) => const _GlobalInventoryNotesDialog(),
            );
            _fetchNote();
          },
        ),
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
            onPressed: () {
              _fetchNote();
              setState(() {
                _dataFuture = _fetchData();
              });
            },
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
    final hasNote = _currentNote.trim().isNotEmpty;

    return RefreshIndicator(
      color: _primary,
      onRefresh: () async {
        _fetchNote();
        setState(() {
          _dataFuture = _fetchData();
        });
        await _dataFuture;
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        itemCount: apartments.length + (hasNote ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          if (hasNote && index == 0) {
            return _NoticesCard(
              initialNote: _currentNote,
              onRefreshRequested: () {},
            );
          }

          final aptIndex = hasNote ? index - 1 : index;
          final apartment = apartments[aptIndex];
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

class _NoticesCard extends StatefulWidget {
  final String initialNote;
  final VoidCallback onRefreshRequested;

  const _NoticesCard({
    required this.initialNote,
    required this.onRefreshRequested,
  });

  @override
  State<_NoticesCard> createState() => _NoticesCardState();
}

class _NoticesCardState extends State<_NoticesCard> {
  late String _currentNote;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentNote = widget.initialNote;
  }

  @override
  void didUpdateWidget(covariant _NoticesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialNote != widget.initialNote) {
      _currentNote = widget.initialNote;
    }
  }

  Future<void> _toggleLine(int index, List<String> lines) async {
    if (_isSaving) return;

    final line = lines[index];
    final isChecked =
        line.trimLeft().startsWith('[x]') || line.trimLeft().startsWith('[X]');
    final displayText = line.replaceFirst(RegExp(r'^\s*\[[xX ]\]\s*'), '');

    lines[index] = isChecked ? '[ ] $displayText' : '[x] $displayText';
    final newNote = lines.join('\n');

    setState(() {
      _currentNote = newNote;
      _isSaving = true;
    });

    await ApiService.saveGlobalInventoryNote(newNote);

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines =
        _currentNote.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notices',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          ...lines.asMap().entries.map((entry) {
            final lineIndex = entry.key;
            final originalLine = entry.value;
            final isChecked =
                originalLine.trimLeft().startsWith('[x]') ||
                originalLine.trimLeft().startsWith('[X]');
            final displayText = originalLine.replaceFirst(
              RegExp(r'^\s*\[[xX ]\]\s*'),
              '',
            );

            return InkWell(
              onTap: () => _toggleLine(lineIndex, lines),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isChecked
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color:
                          isChecked
                              ? Colors.red.shade300
                              : Colors.red.shade700,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          displayText,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color:
                                isChecked
                                    ? Colors.red.shade300
                                    : Colors.red.shade900,
                            decoration:
                                isChecked ? TextDecoration.lineThrough : null,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
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
  bool _loading = true;
  bool _saving = false;
  final _ctrl = TextEditingController();

  static const _primaryDark = Color(0xFF5D8A7A);

  @override
  void initState() {
    super.initState();
    ApiService.fetchGlobalInventoryNote().then((noteStr) {
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
    final ok = await ApiService.saveGlobalInventoryNote(_ctrl.text);
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
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Notices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const SizedBox(
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(color: _primaryDark),
                ),
              )
            else
              Container(
                height: 200,
                padding: const EdgeInsets.all(4),
                child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    hintText: 'Type notices here... (Each line is a checkbox)',
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading || _saving ? null : _saveNotes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save',
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
