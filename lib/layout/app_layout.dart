import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/history_screen.dart';
import '../screens/insights_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/admin_console_screen.dart';
import '../services/ai_admin_service.dart';
import '../services/preferences_service.dart';

class AppLayout extends StatefulWidget {
  const AppLayout({super.key});

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  int _selectedIndex = 0;
  bool _isAdminUser = false;

  List<Widget> get _screens {
    final base = <Widget>[
      const HomeScreen(),
      const HistoryScreen(),
      const InsightsScreen(),
      const ProfileScreen(),
    ];
    if (_isAdminUser) {
      base.add(const AdminConsoleScreen());
    }
    return base;
  }

  List<BottomNavigationBarItem> get _items {
    final base = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home, color: Color(0xFF25D4E4)),
        label: 'HOME',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.history_outlined),
        activeIcon: Icon(Icons.history, color: Color(0xFF25D4E4)),
        label: 'HISTORY',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.insights_outlined),
        activeIcon: Icon(Icons.insights, color: Color(0xFF25D4E4)),
        label: 'INSIGHTS',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.person_outline),
        activeIcon: Icon(Icons.person, color: Color(0xFF25D4E4)),
        label: 'PROFILE',
      ),
    ];
    if (_isAdminUser) {
      base.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.admin_panel_settings_outlined),
          activeIcon: Icon(
            Icons.admin_panel_settings,
            color: Color(0xFF25D4E4),
          ),
          label: 'ADMIN',
        ),
      );
    }
    return base;
  }

  @override
  void initState() {
    super.initState();
    _loadAdminAccess();
  }

  Future<void> _loadAdminAccess() async {
    final storedRole = await PreferencesService.getUserRole();
    if (storedRole != 'admin') {
      if (!mounted) return;
      if (_isAdminUser) {
        setState(() {
          _isAdminUser = false;
          if (_selectedIndex >= _screens.length) {
            _selectedIndex = _screens.length - 1;
          }
        });
      }
      return;
    }

    final access = await AIAdminService.checkAdminAccess();
    if (!mounted) return;

    final isAdmin = access['is_admin'] == true;
    if (_isAdminUser == isAdmin) {
      return;
    }

    setState(() {
      _isAdminUser = isAdmin;
      if (_selectedIndex >= _screens.length) {
        _selectedIndex = _screens.length - 1;
      }
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.blueGrey.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF0B1517).withValues(alpha: 0.9),
          selectedItemColor: const Color(0xFF25D4E4),
          unselectedItemColor: const Color(0xFF64748B),
          selectedLabelStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
          items: _items,
        ),
      ),
    );
  }
}
