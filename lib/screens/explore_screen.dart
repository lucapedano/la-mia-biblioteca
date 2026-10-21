import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../services/local_library_service.dart';
import '../theme.dart';
import 'group_books_screen.dart';

/// "Le mie raccolte": post-it tiles grouped by Tematica or Autore, like the
/// Expo app. Tapping a tile opens the books of that group.
class ExploreScreen extends StatefulWidget {
  final VoidCallback? onOpenAll;
  const ExploreScreen({super.key, this.onOpenAll});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late Future<_ExploreData> _future;
  bool _byAuthor = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadOrder();
  }

  Future<_ExploreData> _load() async {
    final api = context.read<LocalLibraryService>();
    final books = await api.list();
    final favs = await api.favoriteAuthors();
    return _ExploreData(books, favs.toSet());
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _toggleFav(String author) async {
    await context.read<LocalLibraryService>().toggleFavoriteAuthor(author);
    await _reload();
  }

  List<_Group> _groups(_ExploreData d) {
    final map = <String, _Group>{};
    for (final b in d.books) {
      final label = (_byAuthor ? b.author : b.theme).trim();
      if (label.isEmpty) continue;
      if (_query.isNotEmpty &&
          !b.title.toLowerCase().contains(_query) &&
          !b.author.toLowerCase().contains(_query) &&
          !label.toLowerCase().contains(_query)) {
        continue;
      }
      map
          .putIfAbsent(
              label, () => _Group(label, b.color, d.favorites.contains(label)))
          .count++;
    }
    final list = map.values.toList();
    list.sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0
          ? c
          : a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    // Apply the user's custom order (labels not in the saved order go last).
    final ord = _order[_modeKey] ?? const <String>[];
    if (ord.isNotEmpty) {
      final idx = {for (var i = 0; i < ord.length; i++) ord[i]: i};
      list.sort((a, b) =>
          (idx[a.label] ?? 1 << 30).compareTo(idx[b.label] ?? 1 << 30));
    }
    // In author mode favourites stay pinned on top (except while reordering).
    if (_byAuthor && !_reordering) {
      return [
        ...list.where((g) => g.favorite),
        ...list.where((g) => !g.favorite)
      ];
    }
    return list;
  }

  // ---- Custom order ("Riordina") ----------------------------------------
  static const _kOrderPrefix = 'explore_order_';
  bool _reordering = false;
  final Map<String, List<String>> _order = {};
  String get _modeKey => _byAuthor ? 'author' : 'theme';

  Future<void> _loadOrder() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final k in const ['theme', 'author']) {
        _order[k] = p.getStringList('$_kOrderPrefix$k') ?? const [];
      }
    });
  }

  Future<void> _move(List<_Group> groups, int i, int dir) async {
    final j = i + dir;
    if (j < 0 || j >= groups.length) return;
    final labels = groups.map((g) => g.label).toList();
    final tmp = labels[i];
    labels[i] = labels[j];
    labels[j] = tmp;
    setState(() => _order[_modeKey] = labels);
    (await SharedPreferences.getInstance())
        .setStringList('$_kOrderPrefix$_modeKey', labels);
  }

  Future<void> _open(_Group g) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => GroupBooksScreen(
        title: g.label,
        theme: _byAuthor ? null : g.label,
        author: _byAuthor ? g.label : null,
      ),
    ));
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text('Le mie raccolte',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              ),
              _reordering
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44)),
                      onPressed: () => setState(() => _reordering = false),
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Fatto'),
                    )
                  : OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44)),
                      onPressed: () => setState(() => _reordering = true),
                      icon: const Icon(Icons.swap_vert, size: 20),
                      label: const Text('Riordina'),
                    ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Cerca per titolo o autore',
              prefixIcon: Icon(Icons.search),
              filled: true,
              fillColor: AppColors.surfaceTertiary,
              border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.all(Radius.circular(14))),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.all(Radius.circular(14))),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  icon: Icon(Icons.bookmark),
                  label: Text('Tematica')),
              ButtonSegment(
                  value: true, icon: Icon(Icons.person), label: Text('Autore')),
            ],
            selected: {_byAuthor},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _byAuthor = s.first),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<_ExploreData>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _ErrorView(error: '${snap.error}', onRetry: _reload);
              }
              final data = snap.data!;
              if (data.books.isEmpty) {
                return const Center(
                    child: Text('Nessun libro. Aggiungine uno con +'));
              }
              final groups = _groups(data);
              if (_reordering) {
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _ReorderRow(
                    group: groups[i],
                    onUp: i == 0 ? null : () => _move(groups, i, -1),
                    onDown: i == groups.length - 1
                        ? null
                        : () => _move(groups, i, 1),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _reload,
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: _AllBooksTile(
                            count: data.books.length, onTap: widget.onOpenAll),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 1.3,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _GroupTile(
                            group: groups[i],
                            onTap: () => _open(groups[i]),
                            onToggleFav: _byAuthor
                                ? () => _toggleFav(groups[i].label)
                                : null,
                          ),
                          childCount: groups.length,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExploreData {
  final List<Book> books;
  final Set<String> favorites;
  _ExploreData(this.books, this.favorites);
}

class _Group {
  final String label;
  final String color;
  final bool favorite;
  int count = 0;
  _Group(this.label, this.color, this.favorite);
}

/// Row shown in "Riordina" mode: coloured strip with initials and ▲▼ arrows.
class _ReorderRow extends StatelessWidget {
  final _Group group;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  const _ReorderRow({required this.group, this.onUp, this.onDown});

  String get _initials {
    final p = group.label
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (p.isEmpty) return '?';
    if (p.length == 1)
      return p.first.substring(0, p.first.length.clamp(0, 2)).toUpperCase();
    return (p.first[0] + p.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = colorFromHex(group.color);
    final fg = contrastOn(bg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: fg.withValues(alpha: 0.2),
            child: Text(_initials,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w700, fontSize: 16)),
                Text(group.count == 1 ? '1 libro' : '${group.count} libri',
                    style: TextStyle(
                        color: fg.withValues(alpha: 0.8), fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_up,
                color: onUp == null ? fg.withValues(alpha: 0.3) : fg),
            onPressed: onUp,
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down,
                color: onDown == null ? fg.withValues(alpha: 0.3) : fg),
            onPressed: onDown,
          ),
        ],
      ),
    );
  }
}

class _AllBooksTile extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const _AllBooksTile({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tutti i libri',
                        style: TextStyle(
                            color: AppColors.onBrand,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    Text('$count libri',
                        style: const TextStyle(
                            color: AppColors.onBrand, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.onBrand),
            ],
          ),
        ),
      ),
    );
  }
}

/// Post-it tile with a folded top-right corner.
class _GroupTile extends StatelessWidget {
  final _Group group;
  final VoidCallback onTap;
  final VoidCallback? onToggleFav;
  const _GroupTile(
      {required this.group, required this.onTap, this.onToggleFav});

  @override
  Widget build(BuildContext context) {
    final bg = colorFromHex(group.color);
    final fg = contrastOn(bg);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              child: CustomPaint(
                size: const Size(22, 22),
                painter: _FoldPainter(Color.lerp(bg, Colors.black, 0.25)!),
              ),
            ),
            if (onToggleFav != null)
              Positioned(
                top: 0,
                left: 0,
                child: IconButton(
                  icon: Icon(group.favorite ? Icons.star : Icons.star_border,
                      color: fg),
                  onPressed: onToggleFav,
                ),
              ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: fg,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  Text(group.count == 1 ? '1 libro' : '${group.count} libri',
                      style: TextStyle(
                          color: fg.withValues(alpha: 0.8), fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoldPainter extends CustomPainter {
  final Color color;
  _FoldPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _FoldPainter old) => old.color != color;
}

class _ErrorView extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Riprova')),
          ],
        ),
      ),
    );
  }
}
