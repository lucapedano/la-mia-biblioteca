import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme.dart';
import 'book_cover_image.dart';

/// Book card in the style of the Expo app: a coloured cover area (with the
/// cover image when present, otherwise a book icon) and title/author below.
/// The cover area is [Expanded], so the card always fits its grid cell.
class BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback? onTap;
  const BookCard({super.key, required this.book, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = colorFromHex(book.color);
    final fg = contrastOn(bg);
    final hasCover = book.coverUrl != null && book.coverUrl!.isNotEmpty;
    final placeholder = Center(
      child: Icon(Icons.menu_book_outlined, size: 44, color: fg),
    );

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: double.infinity,
                color: bg,
                child: hasCover
                    ? BookCoverImage(
                        path: book.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: placeholder,
                      )
                    : placeholder,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          Text(
            book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Shared grid delegate for book cards (2 columns, cover + 2 text lines).
const kBookGridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 2,
  crossAxisSpacing: 14,
  mainAxisSpacing: 16,
  childAspectRatio: 0.58,
);
