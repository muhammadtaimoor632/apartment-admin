import 'package:flutter/material.dart';
import 'package:wild_atlantic_hub/screens/cleaning_status_page.dart';
import 'package:wild_atlantic_hub/screens/today_checkins_page.dart';
import 'package:wild_atlantic_hub/screens/product_inventory_page.dart';
import 'package:wild_atlantic_hub/screens/booking_calendar_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Keys to control the navigation stack for each tab
  final _cleaningNavKey = GlobalKey<NavigatorState>();
  final _todayNavKey = GlobalKey<NavigatorState>();
  final _inventoryNavKey = GlobalKey<NavigatorState>();
  final _bookingsNavKey = GlobalKey<NavigatorState>();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      Navigator(
        key: _todayNavKey,
        onGenerateRoute: (route) => MaterialPageRoute(
          settings: route,
          builder: (context) => const TodayCheckinsPage(),
        ),
      ),
      Navigator(
        key: _cleaningNavKey,
        onGenerateRoute: (route) => MaterialPageRoute(
          settings: route,
          builder: (context) => const CleaningStatusPage(),
        ),
      ),
      Navigator(
        key: _bookingsNavKey,
        onGenerateRoute: (route) => MaterialPageRoute(
          settings: route,
          builder: (context) => const BookingCalendarPage(),
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
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF8CB2A4),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.today),
            label: 'Today',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checklist_rtl_outlined),
            label: 'Cleaning',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Bookings',
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
    );
  }
}
