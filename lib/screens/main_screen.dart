import 'package:flutter/material.dart';
import 'package:wild_atlantic_hub/screens/cleaning_status_page.dart';
import 'package:wild_atlantic_hub/screens/today_checkins_page.dart';
import 'package:wild_atlantic_hub/screens/product_inventory_page.dart';
import 'package:wild_atlantic_hub/screens/booking_calendar_page.dart';
import 'package:wild_atlantic_hub/screens/guest_requests_page.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wild_atlantic_hub/services/api_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  int _processingOrdersCount = 0;
  Timer? _timer;

  // Keys to control the navigation stack for each tab
  final _cleaningNavKey = GlobalKey<NavigatorState>();
  final _todayNavKey = GlobalKey<NavigatorState>();
  final _inventoryNavKey = GlobalKey<NavigatorState>();
  final _bookingsNavKey = GlobalKey<NavigatorState>();
  final _requestsNavKey = GlobalKey<NavigatorState>();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _fetchProcessingOrdersCount();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchProcessingOrdersCount();
    });
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
      Navigator(
        key: _requestsNavKey,
        onGenerateRoute: (route) => MaterialPageRoute(
          settings: route,
          builder: (context) => const GuestRequestsPage(),
        ),
      ),
    ];
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchProcessingOrdersCount() async {
    try {
      final requests = await ApiService.fetchGuestRequests();
      final prefs = await SharedPreferences.getInstance();
      final completedList = prefs.getStringList('completed_orders') ?? [];
      final completedOrders = completedList.map((e) => int.tryParse(e) ?? 0).toSet();
      
      int count = 0;
      for (var req in requests) {
        if (req.status.toLowerCase() == 'processing' && !completedOrders.contains(req.orderId)) {
          count++;
        }
      }
      
      if (mounted) {
        setState(() {
          _processingOrdersCount = count;
        });
      }
    } catch (e) {
      // Ignore silently for background fetch
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex != index) {
      final keys = [
        _todayNavKey,
        _cleaningNavKey,
        _bookingsNavKey,
        _inventoryNavKey,
        _requestsNavKey,
      ];
      final currentNavKey = keys[_selectedIndex];
      if (currentNavKey.currentState?.canPop() ?? false) {
        currentNavKey.currentState?.pop();
      }
    }
    setState(() {
      _selectedIndex = index;
    });
    if (index == 0) {
      TodayCheckinsPage.refreshStream.add(null);
    }
    // Also fetch the orders count when tapping any tab
    _fetchProcessingOrdersCount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF8CB2A4),
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(icon: Icon(Icons.today), label: 'Today'),
          const BottomNavigationBarItem(
            icon: Icon(Icons.checklist_rtl_outlined),
            label: 'Cleaning',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Bookings',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Inventory',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _processingOrdersCount > 0,
              label: Text('$_processingOrdersCount'),
              child: const Icon(Icons.room_service_outlined),
            ),
            label: 'Requests',
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
