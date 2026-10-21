import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/local_library_service.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/book_cover_image.dart';
import 'book_detail_screen.dart';

/// "Tutti i libri": search, sort, reading-status filter chips and a
/// grid / compact-list toggle (same as the Expo app).
class AllBooksScreen extends StatefulWidget {
  const AllBooksScreen({super.key});

  @override
  State<AllBooksScreen> createState() => _AllBooksScreenState();
}

class _AllBooksScreenState extends State<AllBooksScreen> {
  static const _statusChips = [
    ('', 'Tutti'),
    ('to_read', 'Da leggere'),
    ('reading', 'In corso'),
    ('read', 'Letto'),
  ];

  final _search = TextEditingController();
  String _query = '';
  String _sort = 'date_desc';
  String _status = '';
  bool _list = false;
  late Future<List<Book>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Book>> _load() => context
      .read<LocalLibraryService>()
      .list(search: _query, sort: _sort, status: _status);

  void _reload() => setState(() => _future = _load());

  Future<void> _open(Book b) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: b.id)),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tutti i libri',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    FutureBuilder<List<Book>>(
                      future: _future,
                      builder: (context, snapshot) => snapshot.hasData
                          ? Text(
                              '${snapshot.data!.length} libri',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Ordina',
                icon: const Icon(Icons.swap_vert),
                initialValue: _sort,
                onSelected: (v) {
                  _sort = v;
                  _reload();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'date_desc', child: Text('Più recenti')),
                  PopupMenuItem(value: 'date_asc', child: Text('Più vecchi')),
                  PopupMenuItem(value: 'title_asc', child: Text('Titolo A-Z')),
                  PopupMenuItem(value: 'title_desc', child: Text('Titolo Z-A')),
                  PopupMenuItem(value: 'author_asc', child: Text('Autore A-Z')),
                ],
              ),
              IconButton(
                tooltip: _list ? 'Griglia' : 'Elenco',
                icon:
                    Icon(_list ? Icons.grid_view : Icons.view_agenda_outlined),
                onPressed: () => setState(() => _list = !_list),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _search,
            onChanged: (v) {
              _query = v;
              _reload();
            },
            decoration: const InputDecoration(
              hintText: 'Cerca per titolo o autore',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            children: [
              for (final c in _statusChips)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c.$2),
                    selected: _status == c.$1,
                    showCheckmark: false,
                    onSelected: (_) {
                      _status = c.$1;
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<Book>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('${snap.error}'));
              }
              final books = snap.data ?? const [];
              if (books.isEmpty) {
                return const Center(child: Text('Nessun libro trovato'));
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: _list
                    ? ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                        itemCount: books.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) => _BookRow(
                            book: books[i], onTap: () => _open(books[i])),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                        gridDelegate: kBookGridDelegate,
                        itemCount: books.length,
                        itemBuilder: (context, i) => BookCard(
                            book: books[i], onTap: () => _open(books[i])),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Compact list row: small cover/colour thumbnail, title, author, status.
class _BookRow extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  const _BookRow({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = colorFromHex(book.color);
    final hasCover = book.coverUrl != null && book.coverUrl!.isNotEmpty;
    final placeholder = Center(
        child: Icon(Icons.menu_book_outlined, size: 20, color: contrastOn(bg)));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 44,
                height: 64,
                color: bg,
                child: hasCover
                    ? BookCoverImage(
                        path: book.coverUrl, placeholder: placeholder)
                    : placeholder,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      kStatusLabels[book.status] ?? '',
                      book.theme,
                      if (book.year != null) '${book.year}',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
