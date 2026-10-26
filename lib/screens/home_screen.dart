import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'explore_screen.dart';
import 'all_books_screen.dart';
import 'settings_screen.dart';
import 'add_edit_book_screen.dart';
import 'recent_books_screen.dart';
import '../services/local_library_service.dart';

/// Bottom-tab shell: Esplora, Tutti, Ultimi, Impostazioni + add-book FAB.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  int _recentCount = 0;
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;
  Timer? _recentRefreshTimer;

  // Bump this to force child lists to refresh after add/edit.
  int _refreshTick = 0;
  void _refresh() {
    setState(() => _refreshTick++);
    unawaited(_loadRecentCount());
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1, end: 8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    unawaited(_loadRecentCount());
    _recentRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _loadRecentCount(),
    );
  }

  @override
  void dispose() {
    _recentRefreshTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentCount() async {
    final books =
        await context.read<LocalLibraryService>().list(sort: 'date_desc');
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final count = books.where((book) {
      final created = DateTime.tryParse(book.createdAt ?? '')?.toLocal();
      return created != null && created.isAfter(cutoff);
    }).length;
    if (mounted && count != _recentCount) {
      setState(() => _recentCount = count);
    }
  }

  Widget _recentTabIcon(IconData icon) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (_recentCount > 0)
          Positioned(
            top: -5,
            right: -8,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: const Color(0xFFC62828),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x88C62828),
                      blurRadius: _pulse.value,
                      spreadRadius: _pulse.value / 5,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ExploreScreen(
          key: ValueKey('explore_$_refreshTick'),
          onOpenAll: () => setState(() => _index = 1)),
      AllBooksScreen(key: ValueKey('all_$_refreshTick')),
      RecentBooksScreen(key: ValueKey('recent_$_refreshTick')),
      SettingsScreen(onLibraryChanged: _refresh),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      floatingActionButton: _index == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const AddEditBookScreen()),
                );
                if (changed == true) _refresh();
              },
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() {
            _index = i;
            if (i == 2) _refreshTick++;
          });
          if (i == 2) unawaited(_loadRecentCount());
        },
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Esplora'),
          const NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Tutti'),
          NavigationDestination(
              icon: _recentTabIcon(Icons.new_releases_outlined),
              selectedIcon: _recentTabIcon(Icons.new_releases),
              label: 'Ultimi'),
          const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Impostazioni'),
        ],
      ),
    );
  }
}
