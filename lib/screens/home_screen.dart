import 'package:flutter/material.dart';

import 'explore_screen.dart';
import 'all_books_screen.dart';
import 'settings_screen.dart';
import 'add_edit_book_screen.dart';

/// Bottom-tab shell: Esplora, Tutti, Impostazioni + a FAB to add a book.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  // Bump this to force child lists to refresh after add/edit.
  int _refreshTick = 0;
  void _refresh() => setState(() => _refreshTick++);

  @override
  Widget build(BuildContext context) {
    final pages = [
      ExploreScreen(
          key: ValueKey('explore_$_refreshTick'),
          onOpenAll: () => setState(() => _index = 1)),
      AllBooksScreen(key: ValueKey('all_$_refreshTick')),
      SettingsScreen(onLibraryChanged: _refresh),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      floatingActionButton: _index == 2
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
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Esplora'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Tutti'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Impostazioni'),
        ],
      ),
    );
  }
}
