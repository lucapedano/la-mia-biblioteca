import 'package:flutter_test/flutter_test.dart';
import 'package:la_mia_libreria/utils/isbn.dart';

void main() {
  group('normalizeIsbn', () {
    test('accepts ISBN-10 and ISBN-13 with valid check digits', () {
      expect(normalizeIsbn('0-14-032872-6'), '0140328726');
      expect(normalizeIsbn('978-0-14-032872-1'), '9780140328721');
    });

    test('rejects a 14-digit barcode value', () {
      expect(normalizeIsbn('97888062269685'), isNull);
    });

    test('rejects ISBN-13 with an incorrect check digit', () {
      expect(normalizeIsbn('9788806226968'), isNull);
    });
  });
}
