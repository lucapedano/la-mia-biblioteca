import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/local_library_service.dart';
import '../theme.dart';
import '../widgets/book_cover_image.dart';
import '../widgets/pulse_badge.dart';
import 'book_detail_screen.dart';

class RecentBooksScreen extends StatefulWidget {
  const RecentBooksScreen({super.key});

  @override
  State<RecentBooksScreen> createState() => _RecentBooksScreenState();
}

class _RecentBooksScreenState extends State<RecentBooksScreen> {
  late Future<List<Book>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Book>> _load() async {
    final service = context.read<LocalLibraryService>();
    if (service.isCloudConnected) await service.syncWithCloud();
    final books = await service.list(sort: 'date_desc');
    return books.take(10).toList();
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _open(Book book) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: book.id)),
    );
    if (changed == true) _reload();
  }

  DateTime? _addedAt(Book book) => DateTime.tryParse(book.createdAt ?? '');

  bool _isNew(Book book) {
    final added = _addedAt(book);
    if (added == null) return false;
    final age = DateTime.now().difference(added.toLocal());
    return !age.isNegative && age < const Duration(hours: 24);
  }

  String _dateLabel(Book book) {
    final added = _addedAt(book)?.toLocal();
    if (added == null) return 'Data non disponibile';
    final now = DateTime.now();
    if (now.difference(added) < const Duration(days: 1) &&
        now.day == added.day) {
      return 'Oggi, ${added.hour.toString().padLeft(2, '0')}:'
          '${added.minute.toString().padLeft(2, '0')}';
    }
    return '${added.day.toString().padLeft(2, '0')}/'
        '${added.month.toString().padLeft(2, '0')}/'
        '${added.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Ultimi libri inseriti',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ),
              FutureBuilder<List<Book>>(
                future: _future,
                builder: (context, snapshot) {
                  final newCount = snapshot.data?.where(_isNew).length ?? 0;
                  return newCount > 0
                      ? const PulseBadge(label: 'NUOVI')
                      : const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'I 10 libri aggiunti più di recente alla libreria condivisa.',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
        const Divider(height: 24),
        Expanded(
          child: FutureBuilder<List<Book>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${snapshot.error}', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Riprova'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final books = snapshot.data ?? const [];
              if (books.isEmpty) {
                return const Center(
                  child: Text('Aggiungi un libro per vederlo qui.'),
                );
              }
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  itemCount: books.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _RecentBookRow(
                    book: books[index],
                    isNew: _isNew(books[index]),
                    addedLabel: _dateLabel(books[index]),
                    onTap: () => _open(books[index]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecentBookRow extends StatelessWidget {
  final Book book;
  final bool isNew;
  final String addedLabel;
  final VoidCallback onTap;

  const _RecentBookRow({
    required this.book,
    required this.isNew,
    required this.addedLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(book.color);
    final placeholder = Center(
      child: Icon(
        Icons.menu_book_outlined,
        color: contrastOn(color),
      ),
    );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 7),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: 48,
          height: 64,
          child: ColoredBox(
            color: color,
            child: book.coverUrl?.isNotEmpty == true
                ? BookCoverImage(path: book.coverUrl, placeholder: placeholder)
                : placeholder,
          ),
        ),
      ),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            '${book.theme.isEmpty ? 'Senza tematica' : book.theme} · $addedLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
      trailing: isNew
          ? const PulseBadge(label: 'NUOVO')
          : const Icon(Icons.chevron_right, color: AppColors.muted),
      onTap: onTap,
    );
  }
}
