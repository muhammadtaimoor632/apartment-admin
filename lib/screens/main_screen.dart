import 'package:flutter/material.dart';
import 'package:wild_atlantic_hub/screens/cleaning_status_page.dart';
import 'package:wild_atlantic_hub/screens/product_inventory_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Keys to control the navigation stack for each tab
  final _cleaningNavKey = GlobalKey<NavigatorState>();
  final _inventoryNavKey = GlobalKey<NavigatorState>();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      Navigator(
        key: _cleaningNavKey,
        onGenerateRoute: (route) => MaterialPageRoute(
          settings: route,
          builder: (context) => const CleaningStatusPage(),
        ),
      ),
      Navigator(
        key: _inventoryNavKey,
        onGenerateRoute: (route) => MaterialPageRoute(
          settings: route,
          builder: (context) => const ProductInventoryPage(),
        ),
      ),
    ];
  }

  void _onItemTapped(int index) {
    // If the user taps the currently selected tab, pop to the root of that stack.
    if (index == _selectedIndex) {
      switch (index) {
        case 0:
          _cleaningNavKey.currentState?.popUntil((route) => route.isFirst);
          break;
        case 1:
          _inventoryNavKey.currentState?.popUntil((route) => route.isFirst);
          break;
      }
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  Future<bool> _onWillPop() async {
    final key = _selectedIndex == 0 ? _cleaningNavKey : _inventoryNavKey;
    final navigatorState = key.currentState;

    // 1. Check if the current navigator can be popped.
    if (navigatorState != null && navigatorState.canPop()) {
      navigatorState.pop();
      return false; // Prevents the app from closing.
    }

    // 2. If it can't be popped, and we're not on the first tab, switch to the first tab.
    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
      return false; // Prevents the app from closing.
    }

    // 3. If we are on the first tab and the navigator can't pop, allow the app to close.
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(index: _selectedIndex, children: _pages),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: const Color(0xFF8CB2A4),
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.checklist_rtl_outlined),
              label: 'Cleaning',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              label: 'Inventory',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}