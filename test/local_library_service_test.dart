import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_mia_libreria/services/local_library_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reimport restores same-title editions without duplicating records',
      () async {
    SharedPreferences.setMockInitialValues({});
    final temporaryDirectory = await Directory.systemTemp.createTemp();
    final appDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}app',
    );
    final coversDirectory = Directory(
      '${appDirectory.path}${Platform.pathSeparator}covers',
    );
    await coversDirectory.create(recursive: true);

    final existingCoverBytes = [1, 2, 3];
    final otherEditionCoverBytes = [4, 5, 6];
    final existingCover = File(
      '${coversDirectory.path}${Platform.pathSeparator}existing.jpg',
    );
    await existingCover.writeAsBytes(existingCoverBytes);
    await File(
      '${appDirectory.path}${Platform.pathSeparator}library.json',
    ).writeAsString(
      jsonEncode([
        {
          'id': 'existing-book',
          'title': '4 racconti',
          'author': 'Narrativa Mondiale',
          'theme': 'Narrativa',
          'year': 1977,
          'pages': 502,
          'cover_url': existingCover.path,
        },
      ]),
    );

    final backup = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}backup.json',
    );
    await backup.writeAsString(
      jsonEncode([
        {
          'title': '4 Racconti',
          'author': 'Narrativa Mondiale',
          'theme': 'Narrativa',
          'year': 1977,
          'pages': 502,
          'cover_data': base64Encode(existingCoverBytes),
        },
        {
          'title': '4 racconti',
          'author': 'Narrativa Mondiale',
          'theme': 'Narrativa',
          'year': 1977,
          'pages': 502,
          'cover_data': base64Encode(otherEditionCoverBytes),
        },
        {
          'title': '4 racconti',
          'author': 'Narrativa Mondiale',
          'theme': 'Narrativa',
          'year': 1977,
          'pages': 502,
          'cover_data': base64Encode(existingCoverBytes),
        },
      ]),
    );

    final library = await LocalLibraryService.open(
      supportDirectory: appDirectory,
    );
    try {
      final firstImport = await library.importLibraryFile(backup);
      expect(firstImport.imported, 1);
      expect(firstImport.total, 2);

      final repeatedImport = await library.importLibraryFile(backup);
      expect(repeatedImport.imported, 0);
      expect(repeatedImport.total, 2);

      final books = await library.list();
      expect(books, hasLength(2));
      expect(await library.removeDuplicates(), 0);
    } finally {
      library.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });

  group('book creation duplicate checks', () {
    late Directory temporaryDirectory;
    late LocalLibraryService library;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      temporaryDirectory =
          await Directory.systemTemp.createTemp('biblio-duplicate-test-');
      library = await LocalLibraryService.open(
        supportDirectory: Directory(
          '${temporaryDirectory.path}${Platform.pathSeparator}app',
        ),
      );
    });

    tearDown(() async {
      library.close();
      await temporaryDirectory.delete(recursive: true);
    });

    Map<String, dynamic> book({
      required String title,
      required String author,
      String? isbn,
      int? year,
      int? pages,
    }) =>
        {
          'title': title,
          'author': author,
          'theme': 'Narrativa',
          'isbn': isbn,
          'year': year,
          'pages': pages,
        };

    test('blocks an existing ISBN even when the title differs', () async {
      await library.create(book(
        title: 'Fantastic Mr. Fox',
        author: 'Roald Dahl',
        isbn: '978-0-14-032872-1',
      ));

      await expectLater(
        library.create(book(
          title: 'Un titolo diverso',
          author: 'Altro autore',
          isbn: '9780140328721',
        )),
        throwsA(isA<DuplicateBookException>()),
      );
      expect(await library.list(), hasLength(1));
    });

    test('blocks matching title and author when edition details match',
        () async {
      await library.create(book(
        title: 'Il libro',
        author: 'Autore',
        year: 2020,
        pages: 180,
      ));

      await expectLater(
        library.create(book(
          title: '  IL   LIBRO ',
          author: 'autore',
          year: 2020,
          pages: 180,
        )),
        throwsA(isA<DuplicateBookException>()),
      );
      expect(await library.list(), hasLength(1));
    });

    test('allows a separate edition with a different ISBN', () async {
      await library.create(book(
        title: 'Il libro',
        author: 'Autore',
        isbn: '9780140328721',
      ));

      await library.create(book(
        title: 'Il libro',
        author: 'Autore',
        isbn: '9788806226961',
      ));

      expect(await library.list(), hasLength(2));
    });
  });
}
