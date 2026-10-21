import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/local_library_service.dart';
import '../theme.dart';
import 'add_edit_book_screen.dart';
import '../widgets/book_cover_image.dart';

class BookDetailScreen extends StatefulWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late Future<Book> _future;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<LocalLibraryService>().get(widget.bookId);
  }

  void _reload() {
    setState(
        () => _future = context.read<LocalLibraryService>().get(widget.bookId));
    _changed = true;
  }

  Future<void> _delete() async {
    final library = context.read<LocalLibraryService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina libro'),
        content: const Text('Vuoi davvero eliminare questo libro?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await library.deleteBook(widget.bookId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_changed),
        ),
        title: const Text('Dettaglio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final book = await _future;
              if (!mounted) return;
              final changed = await navigator.push<bool>(
                MaterialPageRoute(
                    builder: (_) => AddEditBookScreen(existing: book)),
              );
              if (changed == true) _reload();
            },
          ),
          IconButton(
              icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: FutureBuilder<Book>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          final b = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (b.coverUrl != null && b.coverUrl!.isNotEmpty)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BookCoverImage(
                      path: b.coverUrl,
                      fit: BoxFit.cover,
                      placeholder: const SizedBox.shrink(),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(b.title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(b.author,
                  style: const TextStyle(fontSize: 16, color: AppColors.muted)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(Icons.category_outlined, b.theme),
                  if (b.year != null) _chip(Icons.event_outlined, '${b.year}'),
                  _chip(Icons.bookmark_border,
                      kStatusLabels[b.status] ?? b.status),
                  if (b.pages != null)
                    _chip(Icons.menu_book_outlined, '${b.pages} pagine'),
                  if (b.location != null && b.location!.isNotEmpty)
                    _chip(Icons.place_outlined, b.location!),
                  if (b.isbn != null && b.isbn!.isNotEmpty)
                    _chip(Icons.qr_code, b.isbn!),
                ],
              ),
              if (b.plot != null && b.plot!.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Trama',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(b.plot!, style: const TextStyle(height: 1.4)),
              ],
              if (b.notes != null && b.notes!.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Note',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(b.notes!, style: const TextStyle(height: 1.4)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Chip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        backgroundColor: AppColors.surfaceTertiary,
        side: BorderSide.none,
      );
}
