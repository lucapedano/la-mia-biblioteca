import 'dart:io';

import 'package:flutter/material.dart';

class BookCoverImage extends StatelessWidget {
  final String? path;
  final BoxFit fit;
  final Widget placeholder;

  const BookCoverImage({
    super.key,
    required this.path,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final value = path;
    if (value == null || value.isEmpty) {
      return placeholder;
    }
    if (value.startsWith('http')) {
      return Image.network(
        value,
        fit: fit,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    final file = value.startsWith('file://')
        ? File.fromUri(Uri.parse(value))
        : File(value);
    return Image.file(
      file,
      fit: fit,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}
