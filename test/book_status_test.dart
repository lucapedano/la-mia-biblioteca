import 'package:flutter_test/flutter_test.dart';
import 'package:la_mia_libreria/models/book.dart';

void main() {
  test('purchase status survives JSON and cloud payload conversion', () {
    final book = Book.fromJson({
      'id': 'purchase-book',
      'title': 'Libro da cercare',
      'author': 'Autore',
      'theme': 'Narrativa',
      'status': 'to_buy',
    });

    expect(book.status, 'to_buy');
    expect(book.toPayload()['status'], 'to_buy');
    expect(kStatusLabels[book.status], 'Da acquistare');
  });
}
