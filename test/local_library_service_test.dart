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
}
