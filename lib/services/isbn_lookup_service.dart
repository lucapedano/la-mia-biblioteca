import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../utils/isbn.dart';

class IsbnBookDetails {
  final String title;
  final String? author;
  final int? year;
  final int? pages;
  final String? plot;
  final String? theme;
  final List<int>? coverBytes;
  final String? coverExtension;

  const IsbnBookDetails({
    required this.title,
    this.author,
    this.year,
    this.pages,
    this.plot,
    this.theme,
    this.coverBytes,
    this.coverExtension,
  });
}

class _NiceBooksLookupResult {
  final IsbnBookDetails? book;
  final List<String> suggestions;

  const _NiceBooksLookupResult({this.book, this.suggestions = const []});
}

class IsbnLookupService {
  static const _timeout = Duration(seconds: 15);
  static const _maxCoverBytes = 20 * 1024 * 1024;
  static const _headers = {
    'User-Agent': 'LaMiaBiblioteca/1.0 (ISBN catalog lookup)',
  };
  static const _niceBooksHeaders = {
    'Accept': 'text/html',
    'Accept-Language': 'it-IT,it;q=0.9',
    'Referer': 'https://nicebooks.com/it/search/isbn',
    'X-Requested-With': 'XMLHttpRequest',
  };

  final http.Client _client;

  IsbnLookupService({http.Client? client}) : _client = client ?? http.Client();

  Future<IsbnBookDetails> lookup(String input) async {
    final isbn = normalizeIsbn(input);
    if (isbn == null) {
      final rawCode = input.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
      if (rawCode.length >= 10 && rawCode.length <= 14) {
        final niceBooks = await _lookupNiceBooks(rawCode);
        if (niceBooks.suggestions.isNotEmpty) {
          throw FormatException(
            'Il codice "$rawCode" non è un ISBN valido. NiceBooks suggerisce: '
            '${niceBooks.suggestions.join(', ')}. Verifica il codice stampato '
            'sul libro e seleziona la forma corretta.',
          );
        }
      }
      throw const FormatException(
        'Inserisci un ISBN-10 o ISBN-13 valido. Il codice deve avere una cifra '
        'di controllo corretta.',
      );
    }

    final results = <IsbnBookDetails>[];
    final errors = <Object>[];
    final isbnCandidates = _isbnCandidates(isbn);

    try {
      final google = await _lookupGoogleBooks(isbn);
      if (google != null) results.add(google);
    } catch (error) {
      errors.add(error);
    }

    if (!_hasPlotAndCover(results)) {
      try {
        final ibs = await _lookupIbs(isbn);
        if (ibs != null) results.add(ibs);
      } catch (error) {
        errors.add(error);
      }
    }

    if (!_hasPlotAndCover(results)) {
      try {
        final niceBooks = await _lookupNiceBooks(isbn);
        if (niceBooks.book != null) results.add(niceBooks.book!);
      } catch (error) {
        errors.add(error);
      }
    }

    if (!_hasPlotAndCover(results)) {
      for (final candidate in isbnCandidates) {
        try {
          final openLibrary = await _lookupOpenLibrary(candidate);
          if (openLibrary != null) results.add(openLibrary);
        } catch (error) {
          errors.add(error);
        }
        if (_hasPlotAndCover(results)) break;
      }
    }

    if (results.every(
          (result) => result.plot == null || result.plot!.length < 180,
        ) ||
        results.every((result) => result.coverBytes == null)) {
      for (final candidate in isbnCandidates) {
        try {
          final openLibraryWork = await _lookupOpenLibraryWork(candidate);
          if (openLibraryWork != null) results.add(openLibraryWork);
        } catch (error) {
          errors.add(error);
        }
        if (_hasPlotAndCover(results)) break;
      }
    }

    if (!_hasPlotAndCover(results)) {
      for (final candidate in isbnCandidates) {
        try {
          final archive = await _lookupInternetArchive(candidate);
          if (archive != null) results.add(archive);
        } catch (error) {
          errors.add(error);
        }
        if (_hasPlotAndCover(results)) break;
      }
    }

    if (results.isNotEmpty) return _combineResults(isbn, results);

    final googleRateLimited = errors.any(
      (error) =>
          error is _CatalogHttpException &&
          error.catalog == 'Google Books' &&
          error.statusCode == 429,
    );
    if (googleRateLimited) {
      throw Exception(
        'Google Books è temporaneamente sovraccarico e gli altri cataloghi '
        'non hanno trovato l’ISBN $isbn. Verifica che il codice mostrato sia '
        'corretto, riprova più tardi o inserisci i dati manualmente.',
      );
    }
    if (errors.isNotEmpty) {
      throw Exception(
        'Ricerca ISBN non disponibile: '
        '${errors.map((error) => error.toString()).join(' ')}',
      );
    }
    throw Exception('Nessun libro trovato per questo ISBN.');
  }

  List<String> _isbnCandidates(String isbn) {
    if (isbn.length == 13 && isbn.startsWith('978')) {
      final isbn10Prefix = isbn.substring(3, 12);
      var sum = 0;
      for (var index = 0; index < isbn10Prefix.length; index++) {
        sum += int.parse(isbn10Prefix[index]) * (10 - index);
      }
      final remainder = sum % 11;
      final checkDigit = remainder == 0 ? '0' : (11 - remainder).toString();
      return [isbn, '$isbn10Prefix$checkDigit'];
    }

    if (isbn.length == 10) {
      final isbn13Prefix = '978${isbn.substring(0, 9)}';
      var sum = 0;
      for (var index = 0; index < isbn13Prefix.length; index++) {
        sum += int.parse(isbn13Prefix[index]) * (index.isEven ? 1 : 3);
      }
      final checkDigit = (10 - sum % 10) % 10;
      return [isbn, '$isbn13Prefix$checkDigit'];
    }

    return [isbn];
  }

  bool _hasPlotAndCover(List<IsbnBookDetails> results) =>
      results.any((result) => result.plot != null) &&
      results.any((result) => result.coverBytes != null);

  IsbnBookDetails _combineResults(
    String isbn,
    List<IsbnBookDetails> results,
  ) {
    T? firstValue<T>(Iterable<T?> values) {
      for (final value in values) {
        if (value != null) return value;
      }
      return null;
    }

    final cover = results.firstWhere(
      (result) => result.coverBytes != null,
      orElse: () => results.first,
    );
    final title = firstValue(
      results
          .map((result) => result.title)
          .where((value) => value.toLowerCase() != 'isbn $isbn'),
    );
    final descriptions = results
        .map((result) => result.plot)
        .whereType<String>()
        .toList()
      ..sort((first, second) => second.length.compareTo(first.length));
    return IsbnBookDetails(
      title: title ?? 'ISBN $isbn',
      author: firstValue(results.map((result) => result.author)),
      year: firstValue(results.map((result) => result.year)),
      pages: firstValue(results.map((result) => result.pages)),
      plot: descriptions.isEmpty ? null : descriptions.first,
      theme: firstValue(results.map((result) => result.theme)),
      coverBytes: cover.coverBytes,
      coverExtension: cover.coverExtension,
    );
  }

  Future<IsbnBookDetails?> _lookupGoogleBooks(String isbn) async {
    final uri = Uri.https(
      'www.googleapis.com',
      '/books/v1/volumes',
      {'q': 'isbn:$isbn', 'maxResults': '1'},
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw _CatalogHttpException('Google Books', response.statusCode);
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['items'] is! List || body['items'].isEmpty) {
      return null;
    }
    final first = body['items'].first;
    if (first is! Map || first['volumeInfo'] is! Map) return null;
    final info = Map<String, dynamic>.from(first['volumeInfo'] as Map);
    final title = _text(info['title']);
    if (title == null) return null;

    final authors = info['authors'];
    final author =
        authors is List && authors.isNotEmpty ? _text(authors.first) : null;
    final categories = info['categories'];
    final category = categories is List && categories.isNotEmpty
        ? _text(categories.first)
        : null;
    final imageLinks = info['imageLinks'];
    final imageUrl = imageLinks is Map
        ? _text(imageLinks['thumbnail']) ?? _text(imageLinks['smallThumbnail'])
        : null;
    final cover = imageUrl == null ? null : await _downloadCover(imageUrl);

    return IsbnBookDetails(
      title: title,
      author: author,
      year: _year(info['publishedDate']),
      pages: _positiveInt(info['pageCount']),
      plot: _text(info['description']),
      theme: category,
      coverBytes: cover?.$1,
      coverExtension: cover?.$2,
    );
  }

  Future<IsbnBookDetails?> _lookupOpenLibrary(String isbn) async {
    final uri = Uri.https(
      'openlibrary.org',
      '/api/books',
      {
        'bibkeys': 'ISBN:$isbn',
        'format': 'json',
        'jscmd': 'data',
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw _CatalogHttpException('Open Library', response.statusCode);
    }

    final body = jsonDecode(response.body);
    if (body is! Map) return null;
    final record = body['ISBN:$isbn'];
    if (record is! Map) return null;

    final authors = record['authors'];
    final author = authors is List && authors.isNotEmpty && authors.first is Map
        ? _text(authors.first['name'])
        : null;
    final publishers = record['publishers'];
    final subjects = record['subjects'];
    final description = record['description'];
    final excerpts = record['excerpts'];
    dynamic firstSentence;
    if (excerpts is List) {
      for (final excerpt in excerpts.whereType<Map>()) {
        if (excerpt['first_sentence'] == true) {
          firstSentence = excerpt['text'];
          break;
        }
      }
      firstSentence ??= excerpts.isNotEmpty && excerpts.first is Map
          ? (excerpts.first as Map)['text']
          : null;
    }
    final cover = record['cover'];
    final coverUrl =
        cover is Map ? _text(cover['large']) ?? _text(cover['medium']) : null;
    final downloadedCover =
        coverUrl == null ? null : await _downloadCover(coverUrl);
    return IsbnBookDetails(
      title: _text(record['title']) ?? 'ISBN $isbn',
      author: author,
      year: _year(record['publish_date']),
      pages: _positiveInt(record['number_of_pages']),
      plot: _text(description is Map ? description['value'] : description) ??
          _text(firstSentence),
      theme: subjects is List && subjects.isNotEmpty && subjects.first is Map
          ? _text(subjects.first['name'])
          : (publishers is List &&
                  publishers.isNotEmpty &&
                  publishers.first is Map
              ? _text(publishers.first['name'])
              : null),
      coverBytes: downloadedCover?.$1,
      coverExtension: downloadedCover?.$2,
    );
  }

  Future<IsbnBookDetails?> _lookupIbs(String isbn) async {
    final searchUri = Uri.https(
      'www.ibs.it',
      '/search/',
      {'query': isbn},
    );
    final searchResponse = await _get(searchUri);
    if (searchResponse.statusCode != 200) {
      throw _CatalogHttpException('IBS', searchResponse.statusCode);
    }

    final escapedIsbn = RegExp.escape(isbn);
    final productAnchor = RegExp(
      '<a\\b(?=[^>]*\\bdata-ean=["\\x27]$escapedIsbn["\\x27])[^>]*>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(searchResponse.body);
    if (productAnchor == null) return null;

    final href = RegExp(
      r'\bhref=["\x27]([^"\x27]+)["\x27]',
      caseSensitive: false,
    ).firstMatch(productAnchor.group(0)!)?.group(1);
    if (href == null) return null;

    final productUri = Uri.parse('https://www.ibs.it').resolve(href);
    final productResponse = await _get(productUri);
    if (productResponse.statusCode != 200) {
      throw _CatalogHttpException('IBS product', productResponse.statusCode);
    }

    final scripts = RegExp(
      r'<script\b[^>]*application/ld\+json[^>]*>(.*?)</script>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(productResponse.body);
    for (final script in scripts) {
      final dynamic decoded;
      try {
        decoded = jsonDecode(script.group(1)!.trim());
      } on FormatException {
        continue;
      }

      final graph = decoded is Map ? decoded['@graph'] : null;
      if (graph is! List) continue;
      for (final item in graph.whereType<Map>()) {
        final type = item['@type'];
        final isBook =
            type == 'Book' || (type is List && type.contains('Book'));
        if (!isBook) continue;

        final author = item['author'];
        final image = item['image'];
        final imageUrl = image is List ? _firstText(image) : _text(image);
        final cover = imageUrl == null ? null : await _downloadCover(imageUrl);
        return IsbnBookDetails(
          title: _text(item['name']) ?? 'ISBN $isbn',
          author: author is Map ? _text(author['name']) : _text(author),
          year: _year(item['datePublished']),
          pages: _positiveInt(item['numberOfPages']),
          plot: _text(item['description']),
          coverBytes: cover?.$1,
          coverExtension: cover?.$2,
        );
      }
    }
    return null;
  }

  Future<_NiceBooksLookupResult> _lookupNiceBooks(String isbn) async {
    final uri = Uri.https(
      'nicebooks.com',
      '/it/search/isbn',
      {'isbn': isbn},
    );
    final response = await _get(uri, headers: _niceBooksHeaders);
    if (response.statusCode != 200) {
      throw _CatalogHttpException('NiceBooks', response.statusCode);
    }

    final body = response.body;
    final resultStart = body.indexOf('class="search-result-line"');
    final suggestions = <String>{};
    for (final match in RegExp(
      r'data-isbn=["\x27](\d{10,13})["\x27]',
      caseSensitive: false,
    ).allMatches(body)) {
      final suggestion = match.group(1)!;
      if (normalizeIsbn(suggestion) != null && suggestion != isbn) {
        suggestions.add(suggestion);
      }
    }
    for (final match in RegExp(
      r'/search/isbn\?isbn=(\d{10,13})',
      caseSensitive: false,
    ).allMatches(body)) {
      final suggestion = match.group(1)!;
      if (normalizeIsbn(suggestion) != null && suggestion != isbn) {
        suggestions.add(suggestion);
      }
    }

    if (resultStart < 0) {
      return _NiceBooksLookupResult(suggestions: suggestions.toList());
    }

    final suggestionsStart =
        body.indexOf('class="isbn-suggestions"', resultStart);
    final resultHtml = body.substring(
      resultStart,
      suggestionsStart < 0 ? body.length : suggestionsStart,
    );
    final titleMatch = RegExp(
      r'<a\b([^>]*\bclass=["\x27][^"\x27]*\btitle\b[^"\x27]*["\x27][^>]*)>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(resultHtml);
    if (titleMatch == null) {
      return _NiceBooksLookupResult(suggestions: suggestions.toList());
    }

    final title = _htmlText(titleMatch.group(2)!);
    if (title.isEmpty) {
      return _NiceBooksLookupResult(suggestions: suggestions.toList());
    }
    final authorMatch = RegExp(
      r'>\s*di\s*<a\b[^>]*\bclass=["\x27][^"\x27]*\bsublinks\b[^"\x27]*["\x27][^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(resultHtml);
    final imageMatch = RegExp(
      r'<img\b[^>]*\bsrc=["\x27]([^"\x27]+)["\x27]',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(resultHtml);
    final imageUrl =
        imageMatch == null ? null : _decodeHtmlEntities(imageMatch.group(1)!);
    final cover = imageUrl == null ? null : await _downloadCover(imageUrl);
    final resultText = _htmlText(resultHtml);
    final pagesMatch =
        RegExp(r'\b(\d+)\s+pag(?:ine|ina)\b', caseSensitive: false)
            .firstMatch(resultText);
    return _NiceBooksLookupResult(
      book: IsbnBookDetails(
        title: title,
        author: authorMatch == null ? null : _htmlText(authorMatch.group(1)!),
        year: _year(resultText),
        pages: pagesMatch == null ? null : _positiveInt(pagesMatch.group(1)),
        coverBytes: cover?.$1,
        coverExtension: cover?.$2,
      ),
      suggestions: suggestions.toList(),
    );
  }

  Future<IsbnBookDetails?> _lookupOpenLibraryWork(String isbn) async {
    final searchUri = Uri.https(
      'openlibrary.org',
      '/search.json',
      {
        'isbn': isbn,
        'fields':
            'key,title,author_name,first_publish_year,number_of_pages_median,cover_i',
        'limit': '5',
      },
    );
    final searchResponse = await _get(searchUri);
    if (searchResponse.statusCode != 200) {
      throw _CatalogHttpException(
        'Open Library search',
        searchResponse.statusCode,
      );
    }
    final searchBody = jsonDecode(searchResponse.body);
    final docs = searchBody is Map ? searchBody['docs'] : null;
    if (docs is! List) return null;

    for (final doc in docs.whereType<Map>()) {
      final key = _text(doc['key']);
      if (key == null || !key.startsWith('/works/')) continue;
      Map? work;
      try {
        final workResponse = await _get(
          Uri.https('openlibrary.org', '$key.json'),
        );
        if (workResponse.statusCode == 200) {
          final decodedWork = jsonDecode(workResponse.body);
          if (decodedWork is Map) work = decodedWork;
        }
      } on http.ClientException {
        // The ISBN search result still contains useful bibliographic data.
      } on TimeoutException {
        // The ISBN search result still contains useful bibliographic data.
      }

      final coverId = _positiveInt(doc['cover_i']);
      final cover = coverId == null
          ? null
          : await _downloadCover(
              'https://covers.openlibrary.org/b/id/$coverId-L.jpg',
            );
      final authors = doc['author_name'];
      return IsbnBookDetails(
        title: _text(doc['title']) ?? 'ISBN $isbn',
        author: _firstText(authors),
        year: _positiveInt(doc['first_publish_year']),
        pages: _positiveInt(doc['number_of_pages_median']),
        plot: _description(work?['description']),
        coverBytes: cover?.$1,
        coverExtension: cover?.$2,
      );
    }
    return null;
  }

  Future<IsbnBookDetails?> _lookupInternetArchive(String isbn) async {
    final uri = Uri.https(
      'archive.org',
      '/advancedsearch.php',
      {
        'q': 'isbn:"$isbn"',
        'fl[]': 'identifier,title,creator,description,year,subject',
        'output': 'json',
        'rows': '25',
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw _CatalogHttpException('Internet Archive', response.statusCode);
    }
    final body = jsonDecode(response.body);
    final responseData = body is Map ? body['response'] : null;
    final docs = responseData is Map ? responseData['docs'] : null;
    if (docs is! List) return null;

    Map? selected;
    var selectedScore = -1;
    for (final item in docs.whereType<Map>()) {
      final title = _text(item['title']);
      final identifier = _text(item['identifier']);
      if (title == null || identifier == null) continue;

      final description = _description(item['description']);
      final creator = item['creator'];
      final author = creator is List ? _firstText(creator) : _text(creator);
      var score = (description == null ? 0 : 2) + (author == null ? 0 : 1);
      if (RegExp(r'donation|pallet', caseSensitive: false).hasMatch(title)) {
        score -= 5;
      }
      if (score > selectedScore) {
        selected = item;
        selectedScore = score;
      }
    }
    if (selected == null) return null;

    final identifier = _text(selected['identifier'])!;
    final creator = selected['creator'];
    final subject = selected['subject'];
    final cover = await _downloadCover(
      'https://archive.org/services/img/${Uri.encodeComponent(identifier)}',
    );
    return IsbnBookDetails(
      title: _text(selected['title'])!,
      author: creator is List ? _firstText(creator) : _text(creator),
      year: _year(selected['year']),
      plot: _description(selected['description']),
      theme: subject is List ? _firstText(subject) : _text(subject),
      coverBytes: cover?.$1,
      coverExtension: cover?.$2,
    );
  }

  Future<(List<int>, String)?> _downloadCover(String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      return null;
    }
    final secureUri =
        parsed.scheme == 'http' ? parsed.replace(scheme: 'https') : parsed;
    try {
      final response = await _get(secureUri);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      if (response.bodyBytes.length > _maxCoverBytes) {
        return null;
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.isNotEmpty && !contentType.startsWith('image/')) {
        return null;
      }
      final extension = switch (contentType) {
        final value when value.contains('png') => '.png',
        final value when value.contains('webp') => '.webp',
        final value when value.contains('gif') => '.gif',
        _ => '.jpg',
      };
      return (response.bodyBytes, extension);
    } on http.ClientException {
      return null;
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on HandshakeException {
      return null;
    }
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) =>
      _client.get(uri, headers: {..._headers, ...headers}).timeout(_timeout);

  String? _text(dynamic value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  String _htmlText(String value) {
    final withoutTags = value.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return _decodeHtmlEntities(withoutTags)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _decodeHtmlEntities(String value) {
    const named = {
      '&amp;': '&',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&lt;': '<',
      '&gt;': '>',
      '&nbsp;': ' ',
    };
    var decoded = value;
    for (final entry in named.entries) {
      decoded = decoded.replaceAll(entry.key, entry.value);
    }
    return decoded.replaceAllMapped(
      RegExp(r'&#(x[0-9a-f]+|\d+);', caseSensitive: false),
      (match) {
        final value = match.group(1)!;
        final codePoint = value.toLowerCase().startsWith('x')
            ? int.tryParse(value.substring(1), radix: 16)
            : int.tryParse(value);
        return codePoint == null
            ? match.group(0)!
            : String.fromCharCode(codePoint);
      },
    );
  }

  String? _firstText(dynamic values) {
    if (values is! List) return null;
    for (final value in values) {
      final text = _text(value);
      if (text != null) return text;
    }
    return null;
  }

  String? _description(dynamic value) {
    final text = _text(value);
    if (text != null) return text;
    if (value is List) {
      final descriptions = value.map(_text).whereType<String>().toList();
      return descriptions.isEmpty ? null : descriptions.join('\n');
    }
    return null;
  }

  int? _year(dynamic value) {
    final match = RegExp(r'\b(1[0-9]{3}|20[0-9]{2})\b')
        .firstMatch(value?.toString() ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  int? _positiveInt(dynamic value) {
    final number = value is int ? value : int.tryParse('$value');
    return number != null && number > 0 ? number : null;
  }

  void close() => _client.close();
}

class _CatalogHttpException implements Exception {
  final String catalog;
  final int statusCode;

  const _CatalogHttpException(this.catalog, this.statusCode);

  @override
  String toString() => '$catalog ha risposto HTTP $statusCode.';
}
