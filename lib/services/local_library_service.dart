import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/book.dart';
import '../utils/isbn.dart';

class LibraryImportResult {
  final int imported;
  final int updated;
  final int total;
  final int covers;

  const LibraryImportResult({
    required this.imported,
    required this.updated,
    required this.total,
    required this.covers,
  });
}

/// Local-first library storage with optional authenticated cloud sync.
class LocalLibraryService {
  static const _favoritesKey = 'favorite_authors';
  static const _lastAutomaticBackupKey = 'last_automatic_backup';
  static const _lastAutomaticBackupErrorKey = 'last_automatic_backup_error';
  static const _backupChannel =
      MethodChannel('it.lamialibreria.la_mia_libreria/backups');
  final File _libraryFile;
  final Directory _coversDirectory;
  List<Book> _books = [];
  Timer? _automaticBackupTimer;
  Timer? _cloudSyncTimer;
  bool _automaticBackupRunning = false;
  bool _automaticBackupPending = false;
  final SupabaseClient? _cloudClient;
  StreamSubscription<AuthState>? _authSubscription;
  Future<void>? _cloudSyncFuture;
  String? _cloudSyncError;

  LocalLibraryService._(
    this._libraryFile,
    this._coversDirectory,
    this._cloudClient,
  );

  static Future<LocalLibraryService> open({
    Directory? supportDirectory,
    SupabaseClient? cloudClient,
  }) async {
    final directory =
        supportDirectory ?? await getApplicationSupportDirectory();
    final covers =
        Directory('${directory.path}${Platform.pathSeparator}covers');
    await covers.create(recursive: true);
    final service = LocalLibraryService._(
      File('${directory.path}${Platform.pathSeparator}library.json'),
      covers,
      cloudClient,
    );
    await service._load();
    if (cloudClient != null) {
      service._startCloudSync();
      if (cloudClient.auth.currentUser != null) {
        await service._syncInBackground();
      }
    }
    return service;
  }

  bool get isCloudConfigured => _cloudClient != null;
  bool get isCloudConnected => _cloudClient?.auth.currentUser != null;
  String? get cloudEmail => _cloudClient?.auth.currentUser?.email;
  String? get cloudSyncError => _cloudSyncError;

  void _startCloudSync() {
    final client = _cloudClient;
    if (client == null) return;
    _authSubscription = client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        unawaited(_syncInBackground());
      }
    });
    _cloudSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (client.auth.currentUser != null) {
        unawaited(_syncInBackground());
      }
    });
  }

  Future<void> _syncInBackground() async {
    try {
      await syncWithCloud();
    } catch (error) {
      _cloudSyncError = '$error';
    }
  }

  Future<void> syncWithCloud() {
    final current = _cloudSyncFuture;
    if (current != null) return current;
    final operation = _syncWithCloud();
    _cloudSyncFuture = operation;
    return operation.whenComplete(() => _cloudSyncFuture = null);
  }

  Future<void> _syncWithCloud() async {
    final client = _cloudClient;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Accedi a Supabase prima di sincronizzare.');
    }

    final rows = await client.from('books').select().eq('user_id', user.id);
    final remoteBooks = <String, Book>{};
    final remoteTombstones = <String, DateTime>{};
    for (final row in rows) {
      final record = Map<String, dynamic>.from(row);
      final deletedAt = DateTime.tryParse('${record['deleted_at'] ?? ''}');
      final id = (record['id'] ?? '').toString();
      if (deletedAt != null) {
        remoteTombstones[id] = deletedAt;
      } else {
        final coverPath = record['cover_path']?.toString();
        if (coverPath != null && coverPath.isNotEmpty) {
          record['cloud_cover_path'] = coverPath;
          Book? existingLocal;
          for (final local in _books) {
            if (local.id == id) {
              existingLocal = local;
              break;
            }
          }
          if (existingLocal?.cloudCoverPath == coverPath &&
              await _hasLocalCover(existingLocal?.coverUrl)) {
            record['cover_url'] = existingLocal!.coverUrl;
          } else {
            final coverBytes =
                await client.storage.from('book-covers').download(coverPath);
            record['cover_url'] = await saveCover(
              coverBytes,
              coverPath.split('/').last,
            );
          }
        }
        final book = Book.fromJson(record);
        remoteBooks[book.id] = book;
      }
    }

    if (rows.isEmpty) {
      await _uploadBooks(_books);
      _cloudSyncError = null;
      return;
    }

    final merged = <String, Book>{...remoteBooks};
    final pendingUploads = <Book>[];
    for (final local in _books) {
      final remote = remoteBooks[local.id];
      final deletedAt = remoteTombstones[local.id];
      if (deletedAt != null &&
          !_isNewer(local.updatedAt, deletedAt.toIso8601String())) {
        merged.remove(local.id);
      } else if (remote == null ||
          _isNewer(local.updatedAt, remote.updatedAt)) {
        merged[local.id] = local;
        pendingUploads.add(local);
      }
    }
    _books = merged.values.toList();
    await _writeLocalLibrary();
    await _uploadBooks(pendingUploads);
    _cloudSyncError = null;
  }

  Future<void> _uploadBooks(Iterable<Book> books) async {
    final client = _cloudClient;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    final records = <Map<String, dynamic>>[];
    for (final book in books) {
      var coverPath = book.cloudCoverPath;
      final cover = book.coverUrl;
      if (coverPath == null &&
          cover != null &&
          cover.isNotEmpty &&
          !cover.startsWith('http')) {
        final file = _coverFile(cover);
        if (await file.exists()) {
          final extension = file.path.contains('.')
              ? file.path.substring(file.path.lastIndexOf('.'))
              : '.jpg';
          coverPath = '${user.id}/${book.id}$extension';
          await client.storage.from('book-covers').uploadBinary(
                coverPath,
                Uint8List.fromList(await file.readAsBytes()),
                fileOptions: const FileOptions(upsert: true),
              );
          final index = _books.indexWhere((item) => item.id == book.id);
          if (index >= 0) {
            _books[index] = Book.fromJson({
              ..._books[index].toJson(),
              'cloud_cover_path': coverPath,
            });
          }
        }
      }
      final record = <String, dynamic>{
        ...book.toJson(),
        'updated_at': book.updatedAt ??
            book.createdAt ??
            DateTime.now().toUtc().toIso8601String(),
        'user_id': user.id,
        'cover_url': coverPath == null && cover?.startsWith('http') == true
            ? cover
            : null,
        'cover_path': coverPath,
        'deleted_at': null,
      };
      record.remove('cloud_cover_path');
      records.add(record);
    }
    await _writeLocalLibrary();
    if (records.isNotEmpty) {
      await client.from('books').upsert(records, onConflict: 'user_id,id');
    }
    _cloudSyncError = null;
  }

  bool _isNewer(String? first, String? second) {
    final firstDate = DateTime.tryParse(first ?? '');
    final secondDate = DateTime.tryParse(second ?? '');
    if (firstDate == null) return false;
    if (secondDate == null) return true;
    return firstDate.isAfter(secondDate);
  }

  Future<void> _writeLocalLibrary() async {
    await _libraryFile.writeAsString(
      jsonEncode(_books.map((book) => book.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> _load() async {
    if (!await _libraryFile.exists()) return;
    final decoded = jsonDecode(await _libraryFile.readAsString());
    if (decoded is! List) {
      throw const FormatException('Il file della libreria non è valido.');
    }
    _books = decoded
        .map((item) => Book.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> _persist() async {
    await _writeLocalLibrary();
    _scheduleAutomaticBackup();
  }

  void _scheduleAutomaticBackup() {
    _automaticBackupTimer?.cancel();
    _automaticBackupTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_writeAutomaticBackup());
    });
  }

  Future<void> createAutomaticBackup() => _writeAutomaticBackup();

  void close() {
    _automaticBackupTimer?.cancel();
    _cloudSyncTimer?.cancel();
    unawaited(_authSubscription?.cancel());
  }

  Future<void> _writeAutomaticBackup() async {
    if (_automaticBackupRunning) {
      _automaticBackupPending = true;
      return;
    }
    _automaticBackupRunning = true;
    try {
      do {
        _automaticBackupPending = false;
        final now = DateTime.now();
        final name = 'LaMiaLibreria-Auto-${_dateStamp(now)}.json';
        await _saveBackup(name, automatic: true);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastAutomaticBackupKey, now.toIso8601String());
        await prefs.remove(_lastAutomaticBackupErrorKey);
      } while (_automaticBackupPending);
    } catch (error) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastAutomaticBackupErrorKey, '$error');
    } finally {
      _automaticBackupRunning = false;
    }
  }

  Future<Map<String, String?>> automaticBackupStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'last': prefs.getString(_lastAutomaticBackupKey),
      'error': prefs.getString(_lastAutomaticBackupErrorKey),
    };
  }

  Future<List<Map<String, dynamic>>> listBackups() async {
    final result =
        await _backupChannel.invokeMethod<List<dynamic>>('listBackups');
    return (result ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<String> createManualBackup() async {
    final now = DateTime.now();
    final name =
        'LaMiaLibreria-Manuale-${_dateStamp(now)}-${_timeStamp(now)}.json';
    await _saveBackup(name, automatic: false);
    return name;
  }

  Future<String> _saveBackup(String name, {required bool automatic}) async {
    final backup = await _exportLibraryToFile();
    try {
      await _backupChannel.invokeMethod<String>('saveBackup', {
        'path': backup.path,
        'name': name,
        'automatic': automatic,
      });
    } finally {
      if (await backup.exists()) await backup.delete();
    }
    return name;
  }

  Future<File> _exportLibraryToFile() async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'library-backup-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    final sink = file.openWrite();
    try {
      final prefs = await SharedPreferences.getInstance();
      final books = List<Book>.of(_books);
      sink.write('{"format":"la_mia_libreria","version":1,"books":[');
      for (var index = 0; index < books.length; index++) {
        if (index > 0) sink.write(',');
        final book = books[index];
        final entry = book.toJson();
        final cover = book.coverUrl;
        if (cover != null && cover.isNotEmpty && !cover.startsWith('http')) {
          final coverFile = cover.startsWith('file://')
              ? File.fromUri(Uri.parse(cover))
              : File(cover);
          if (await coverFile.exists()) {
            entry['cover_data'] = base64Encode(await coverFile.readAsBytes());
          }
        }
        sink.write(jsonEncode(entry));
      }
      sink.write('],"favorite_authors":');
      sink.write(jsonEncode(prefs.getStringList(_favoritesKey) ?? []));
      sink.write('}');
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    await sink.close();
    return file;
  }

  String _dateStamp(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _timeStamp(DateTime date) => '${date.hour.toString().padLeft(2, '0')}'
      '${date.minute.toString().padLeft(2, '0')}'
      '${date.second.toString().padLeft(2, '0')}';

  Future<List<Book>> list({
    String? search,
    String? theme,
    String? author,
    String? status,
    String sort = 'date_desc',
  }) async {
    final query = search?.trim().toLowerCase() ?? '';
    final result = _books.where((book) {
      return (query.isEmpty ||
              book.title.toLowerCase().contains(query) ||
              book.author.toLowerCase().contains(query)) &&
          (theme == null || book.theme == theme) &&
          (author == null || book.author == author) &&
          (status == null || status.isEmpty || book.status == status);
    }).toList();

    result.sort((a, b) {
      switch (sort) {
        case 'date_asc':
          return (a.createdAt ?? '').compareTo(b.createdAt ?? '');
        case 'title_asc':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'title_desc':
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        case 'author_asc':
          return a.author.toLowerCase().compareTo(b.author.toLowerCase());
        default:
          return (b.createdAt ?? '').compareTo(a.createdAt ?? '');
      }
    });
    return result;
  }

  Future<Book> get(String id) async {
    return _books.firstWhere(
      (book) => book.id == id,
      orElse: () => throw StateError('Libro non trovato.'),
    );
  }

  Future<Book> create(Map<String, dynamic> payload) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final book = Book.fromJson({
      ...payload,
      'id': _newBookId(),
      'created_at': now,
      'updated_at': now,
    });
    _books.add(book);
    await _persist();
    await _uploadAfterLocalSave([book]);
    return book;
  }

  Future<Book> update(String id, Map<String, dynamic> payload) async {
    final index = _books.indexWhere((book) => book.id == id);
    if (index < 0) throw StateError('Libro non trovato.');
    final current = _books[index];
    final update = <String, dynamic>{
      ...current.toJson(),
      ...payload,
      'id': current.id,
      'created_at': current.createdAt,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (payload.containsKey('cover_url') &&
        payload['cover_url'] != current.coverUrl) {
      update['cloud_cover_path'] = null;
    }
    _books[index] = Book.fromJson(update);
    await _persist();
    await _uploadAfterLocalSave([_books[index]]);
    return _books[index];
  }

  Future<void> _uploadAfterLocalSave(Iterable<Book> books) async {
    try {
      await _uploadBooks(books);
    } catch (error) {
      _cloudSyncError = '$error';
      throw StateError(
        'Modifica salvata sul dispositivo, ma non sincronizzata: $error',
      );
    }
  }

  Future<void> deleteBook(String id) async {
    final index = _books.indexWhere((book) => book.id == id);
    if (index < 0) throw StateError('Libro non trovato.');
    final client = _cloudClient;
    final user = client?.auth.currentUser;
    if (client != null && user != null) {
      await client
          .from('books')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', user.id)
          .eq('id', id);
    }
    _books.removeAt(index);
    await _persist();
  }

  Future<int> clearLibrary() async {
    final count = _books.length;
    final client = _cloudClient;
    final user = client?.auth.currentUser;
    if (client != null && user != null) {
      await client
          .from('books')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', user.id)
          .isFilter('deleted_at', null);
    }
    _books = [];
    await _persist();
    for (final entity in _coversDirectory.listSync()) {
      if (entity is File) await entity.delete();
    }
    return count;
  }

  Future<String> saveCover(List<int> bytes, String filename) async {
    final extension = filename.contains('.')
        ? filename.substring(filename.lastIndexOf('.')).toLowerCase()
        : '.jpg';
    final safeExtension =
        RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension) ? extension : '.jpg';
    final file = File(
      '${_coversDirectory.path}${Platform.pathSeparator}'
      '${DateTime.now().microsecondsSinceEpoch}$safeExtension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<List<String>> favoriteAuthors() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoritesKey) ?? [];
  }

  Future<List<String>> toggleFavoriteAuthor(String author) async {
    final favorites = (await favoriteAuthors()).toSet();
    if (!favorites.add(author)) favorites.remove(author);
    final result = favorites.toList()..sort();
    await (await SharedPreferences.getInstance())
        .setStringList(_favoritesKey, result);
    _scheduleAutomaticBackup();
    return result;
  }

  Future<int> removeDuplicates() async {
    final unique = <Book>[];
    final indicesByKey = <String, List<int>>{};
    for (final book in _books) {
      final key = _bookKey(book);
      final candidates = indicesByKey[key] ?? const <int>[];
      int? matchIndex;
      for (final index in candidates) {
        if (await _areSameBook(unique[index], book)) {
          matchIndex = index;
          break;
        }
      }
      if (matchIndex == null) {
        indicesByKey.putIfAbsent(key, () => []).add(unique.length);
        unique.add(book);
      } else {
        unique[matchIndex] = _mergeDuplicate(unique[matchIndex], book);
      }
    }
    final removed = _books.length - unique.length;
    if (removed > 0) {
      final keptIds = unique.map((book) => book.id).toSet();
      final client = _cloudClient;
      final user = client?.auth.currentUser;
      if (client != null && user != null) {
        final deletedAt = DateTime.now().toUtc().toIso8601String();
        for (final book in _books) {
          if (keptIds.contains(book.id)) continue;
          await client
              .from('books')
              .update({'deleted_at': deletedAt})
              .eq('user_id', user.id)
              .eq('id', book.id);
        }
      }
      _books = unique;
      await _persist();
      await _uploadAfterLocalSave(_books);
    }
    return removed;
  }

  Book _mergeDuplicate(Book first, Book second) {
    return Book(
      id: first.id,
      title: first.title,
      author: first.author,
      theme: _preferText(first.theme, second.theme) ?? '',
      year: first.year ?? second.year,
      color: first.color,
      pages: first.pages ?? second.pages,
      status: first.status,
      plot: _preferText(first.plot, second.plot),
      notes: _preferText(first.notes, second.notes),
      location: _preferText(first.location, second.location),
      coverUrl: _preferCover(first.coverUrl, second.coverUrl),
      isbn: _preferText(first.isbn, second.isbn),
      createdAt: first.createdAt ?? second.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      cloudCoverPath: first.cloudCoverPath ?? second.cloudCoverPath,
    );
  }

  String? _preferCover(String? first, String? second) {
    final firstIsRemote = first?.startsWith('http') ?? false;
    final secondIsRemote = second?.startsWith('http') ?? false;
    if (firstIsRemote && !secondIsRemote) return second;
    return _preferText(first, second);
  }

  String? _preferText(String? first, String? second) =>
      first != null && first.trim().isNotEmpty ? first : second;

  Future<LibraryImportResult> importLibraryFile(File source) async {
    if (!await source.exists()) {
      throw const FileSystemException('Il file selezionato non è disponibile.');
    }
    final input = await source.open();
    final signature = await input.read(4);
    await input.close();
    if (_isZip(signature)) {
      final stream = InputFileStream(source.path);
      try {
        final archive = ZipDecoder().decodeStream(stream);
        final archiveFiles = <String, ArchiveFile>{};
        var totalSize = 0;
        for (final file in archive) {
          if (!file.isFile) continue;
          totalSize += file.size;
          if (totalSize > 512 * 1024 * 1024) {
            throw const FormatException(
              'Il contenuto del backup ZIP è troppo grande.',
            );
          }
          archiveFiles[file.name.replaceAll('\\', '/').toLowerCase()] = file;
        }
        final decoded = _findBooksJson(archiveFiles);
        return await _importDecoded(decoded, archiveFiles);
      } finally {
        await stream.close();
      }
    }
    if (await source.length() > 128 * 1024 * 1024) {
      throw const FormatException('Il file JSON supera il limite di 128 MB.');
    }
    final decoded = jsonDecode(await source.readAsString());
    return _importDecoded(decoded, const {});
  }

  Future<LibraryImportResult> _importDecoded(
    dynamic decoded,
    Map<String, ArchiveFile> archiveFiles,
  ) async {
    final rawBooks = decoded is List
        ? decoded
        : decoded is Map
            ? decoded['books'] ?? decoded['data']
            : null;
    if (rawBooks is! List) {
      throw const FormatException('Il backup non contiene una lista di libri.');
    }

    final imported = <Book>[];
    for (final raw in rawBooks) {
      if (raw is! Map) {
        throw const FormatException('Un elemento del backup non è valido.');
      }
      final data = Map<String, dynamic>.from(raw);
      final title = (data['title'] ?? '').toString().trim();
      final author = (data['author'] ?? '').toString().trim();
      if (title.isEmpty || author.isEmpty) {
        throw const FormatException('Ogni libro deve avere titolo e autore.');
      }
      final coverData = _readCoverData(data);
      if (data['cover_url'] == null || data['cover_url'].toString().isEmpty) {
        for (final key in const [
          'coverUrl',
          'cover',
          'cover_path',
          'cover_file',
          'cover_filename',
          'image',
          'image_url',
          'imageUrl',
          'image_path',
          'image_filename',
          'thumbnail_url',
          'thumbnail',
        ]) {
          final value = data[key];
          if (value is String && value.trim().isNotEmpty) {
            data['cover_url'] = value.trim();
            break;
          }
        }
      }

      if (coverData is String && coverData.isNotEmpty) {
        final encoded = coverData.contains(',')
            ? coverData.substring(coverData.indexOf(',') + 1)
            : coverData;
        final coverBytes = base64Decode(encoded);
        if (coverBytes.length > 20 * 1024 * 1024) {
          throw const FormatException(
              'Una copertina supera il limite di 20 MB.');
        }
        data['cover_url'] = await saveCover(coverBytes, 'imported.jpg');
      } else {
        final coverReference = (data['cover_file'] ??
                data['cover_url'] ??
                data['coverUrl'] ??
                data['image'] ??
                data['image_url'] ??
                data['imageUrl'] ??
                data['cover_path'] ??
                data['cover_filename'] ??
                data['image_path'] ??
                data['image_filename'] ??
                data['thumbnail_url'] ??
                data['thumbnail'] ??
                '')
            .toString();
        final archivedCover = _findCover(archiveFiles, coverReference);
        if (archivedCover != null) {
          if (archivedCover.$2.size > 20 * 1024 * 1024) {
            throw const FormatException(
              'Una copertina supera il limite di 20 MB.',
            );
          }
          final coverBytes = archivedCover.$2.readBytes();
          if (coverBytes == null) {
            throw const FormatException('Impossibile leggere una copertina.');
          }
          data['cover_url'] = await saveCover(
            coverBytes,
            archivedCover.$1,
          );
          archivedCover.$2.clear();
        } else if (coverReference.isNotEmpty &&
            !await File(coverReference).exists()) {
          data['cover_url'] = null;
        }
      }
      final id = (data['id'] ?? '').toString();
      if (id.isEmpty ||
          _books.any((book) => book.id == id) ||
          imported.any((book) => book.id == id)) {
        data['id'] = _newBookId(imported.map((book) => book.id));
      }
      imported.add(Book.fromJson(data));
    }

    final indicesByKey = <String, List<int>>{};
    for (var index = 0; index < _books.length; index++) {
      indicesByKey.putIfAbsent(_bookKey(_books[index]), () => []).add(index);
    }
    var addedCount = 0;
    var updatedCount = 0;
    var coverCount = 0;
    for (final incoming in imported) {
      final key = _bookKey(incoming);
      final candidates = indicesByKey[key] ?? const <int>[];
      int? existingIndex;
      for (final index in candidates) {
        if (await _areSameBook(_books[index], incoming)) {
          existingIndex = index;
          break;
        }
      }
      if (existingIndex == null) {
        indicesByKey.putIfAbsent(key, () => []).add(_books.length);
        _books.add(incoming);
        addedCount++;
        if (await _hasLocalCover(incoming.coverUrl)) coverCount++;
        continue;
      }

      final existing = _books[existingIndex];
      if (!await _hasLocalCover(existing.coverUrl) &&
          await _hasLocalCover(incoming.coverUrl)) {
        _books[existingIndex] = Book.fromJson({
          ...existing.toJson(),
          'cover_url': incoming.coverUrl,
        });
        updatedCount++;
        coverCount++;
      }
    }
    if (addedCount > 0 || updatedCount > 0) {
      await _persist();
      await _uploadBooks(_books);
    }

    if (decoded is Map && decoded['favorite_authors'] is List) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _favoritesKey,
        List<String>.from(decoded['favorite_authors']),
      );
    }
    return LibraryImportResult(
      imported: addedCount,
      updated: updatedCount,
      total: _books.length,
      covers: coverCount,
    );
  }

  String _bookKey(Book book) =>
      '${book.title.trim().toLowerCase()}|${book.author.trim().toLowerCase()}';

  Future<bool> _areSameBook(Book first, Book second) async {
    final firstIsbn = normalizeIsbn(first.isbn ?? '');
    final secondIsbn = normalizeIsbn(second.isbn ?? '');
    if (firstIsbn != null && secondIsbn != null && firstIsbn != secondIsbn) {
      return false;
    }
    if (first.year != null &&
        second.year != null &&
        first.year != second.year) {
      return false;
    }
    if (first.pages != null &&
        second.pages != null &&
        first.pages != second.pages) {
      return false;
    }

    final firstCover = first.coverUrl;
    final secondCover = second.coverUrl;
    if (firstCover == null ||
        firstCover.isEmpty ||
        secondCover == null ||
        secondCover.isEmpty) {
      return true;
    }
    if (firstCover.startsWith('http') && secondCover.startsWith('http')) {
      return firstCover == secondCover;
    }

    final firstFile = _coverFile(firstCover);
    final secondFile = _coverFile(secondCover);
    if (!await firstFile.exists() || !await secondFile.exists()) return true;
    final firstLength = await firstFile.length();
    if (firstLength != await secondFile.length()) return false;
    final firstBytes = await firstFile.readAsBytes();
    final secondBytes = await secondFile.readAsBytes();
    for (var index = 0; index < firstBytes.length; index++) {
      if (firstBytes[index] != secondBytes[index]) return false;
    }
    return true;
  }

  File _coverFile(String path) =>
      path.startsWith('file://') ? File.fromUri(Uri.parse(path)) : File(path);

  Future<bool> _hasLocalCover(String? value) async {
    if (value == null || value.isEmpty || value.startsWith('http')) {
      return false;
    }
    return _coverFile(value).exists();
  }

  String? _readCoverData(Map<String, dynamic> data) {
    for (final key in const [
      'cover_data',
      'cover_base64',
      'image_base64',
    ]) {
      final value = data.remove(key);
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  bool _isZip(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      const {
        0x03,
        0x05,
        0x07,
      }.contains(bytes[2]) &&
      const {
        0x04,
        0x06,
        0x08,
      }.contains(bytes[3]);

  dynamic _findBooksJson(Map<String, ArchiveFile> archiveFiles) {
    for (final entry in archiveFiles.entries) {
      if (!entry.key.endsWith('.json')) continue;
      if (entry.value.size > 128 * 1024 * 1024) {
        continue;
      }
      final dynamic decoded;
      try {
        final contents = entry.value.readBytes();
        if (contents == null) continue;
        decoded = jsonDecode(utf8.decode(contents));
      } on FormatException {
        continue;
      }
      entry.value.clear();
      if (_bookList(decoded) != null) return decoded;
    }
    throw const FormatException(
      'Nel file ZIP non è stato trovato un backup JSON con i libri.',
    );
  }

  List? _bookList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      if (decoded['books'] is List) return decoded['books'] as List;
      if (decoded['data'] is List) return decoded['data'] as List;
    }
    return null;
  }

  (String, ArchiveFile)? _findCover(
    Map<String, ArchiveFile> archiveFiles,
    String reference,
  ) {
    if (archiveFiles.isEmpty || reference.isEmpty) return null;
    final uri = Uri.tryParse(reference);
    final rawPath = (uri?.hasScheme == true ? uri!.path : reference)
        .split('?')
        .first
        .replaceAll('\\', '/');
    String decodedPath;
    try {
      decodedPath = Uri.decodeComponent(rawPath).toLowerCase();
    } on FormatException {
      decodedPath = rawPath.toLowerCase();
    }
    final normalized =
        decodedPath.startsWith('/') ? decodedPath.substring(1) : decodedPath;
    final candidates = <String>{
      normalized,
      if (normalized.contains('/files/'))
        normalized.substring(normalized.indexOf('/files/') + 7),
      if (normalized.contains('/covers/'))
        normalized.substring(normalized.indexOf('/covers/') + 8),
    };
    for (final candidate in candidates) {
      final direct = archiveFiles[candidate];
      if (direct != null) return (candidate, direct);
      for (final entry in archiveFiles.entries) {
        if (entry.key.endsWith('/$candidate')) return (entry.key, entry.value);
      }
    }
    final filename = normalized.split('/').last;
    for (final entry in archiveFiles.entries) {
      if (entry.key == filename || entry.key.split('/').last == filename) {
        return (entry.key, entry.value);
      }
    }
    return null;
  }

  String _newBookId([Iterable<String> reserved = const []]) {
    final ids = _books.map((book) => book.id).toSet();
    ids.addAll(reserved);
    var id = DateTime.now().microsecondsSinceEpoch.toString();
    while (ids.contains(id)) {
      id = (int.parse(id) + 1).toString();
    }
    return id;
  }
}
