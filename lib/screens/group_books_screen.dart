import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/local_library_service.dart';
import '../widgets/book_card.dart';
import 'book_detail_screen.dart';

/// Books of a single theme or author (opened from an Esplora tile).
class GroupBooksScreen extends StatefulWidget {
  final String title;
  final String? theme;
  final String? author;
  const GroupBooksScreen(
      {super.key, required this.title, this.theme, this.author});

  @override
  State<GroupBooksScreen> createState() => _GroupBooksScreenState();
}

class _GroupBooksScreenState extends State<GroupBooksScreen> {
  late Future<List<Book>> _future;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Book>> _load() => context
      .read<LocalLibraryService>()
      .list(theme: widget.theme, author: widget.author, sort: 'title_asc');

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: FutureBuilder<List<Book>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final books = snap.data ?? const [];
            if (books.isEmpty) return const Center(child: Text('Nessun libro'));
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              gridDelegate: kBookGridDelegate,
              itemCount: books.length,
              itemBuilder: (context, i) => BookCard(
                book: books[i],
                onTap: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                        builder: (_) => BookDetailScreen(bookId: books[i].id)),
                  );
                  if (changed == true) {
                    _changed = true;
                    setState(() => _future = _load());
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
