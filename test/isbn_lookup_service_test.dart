import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_mia_libreria/services/isbn_lookup_service.dart';

void main() {
  group('IsbnLookupService', () {
    test('loads Google Books metadata, plot, and cover', () async {
      Uri? requestedCoverUri;
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'volumeInfo': {
                      'title': 'The Book',
                      'authors': ['A. Author'],
                      'publishedDate': '2020-04-01',
                      'pageCount': 123,
                      'description': 'A book plot.',
                      'categories': ['Fiction'],
                      'imageLinks': {
                        'thumbnail': 'http://covers.example/book.jpg',
                      },
                    },
                  },
                ],
              }),
              200,
            );
          }
          requestedCoverUri = request.url;
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );

      final result = await service.lookup('978-0-14-032872-1');

      expect(result.title, 'The Book');
      expect(result.author, 'A. Author');
      expect(result.year, 2020);
      expect(result.pages, 123);
      expect(result.plot, 'A book plot.');
      expect(result.theme, 'Fiction');
      expect(result.coverBytes, [1, 2, 3]);
      expect(result.coverExtension, '.jpg');
      expect(requestedCoverUri?.scheme, 'https');
      service.close();
    });

    test('keeps metadata when optional cover download fails', () async {
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'volumeInfo': {
                      'title': 'Book with unavailable cover',
                      'authors': ['A. Author'],
                      'description': 'A full book description.',
                      'imageLinks': {
                        'thumbnail': 'https://covers.example/unavailable.jpg',
                      },
                    },
                  },
                ],
              }),
              200,
            );
          }
          throw http.ClientException('Cover server unavailable');
        }),
      );

      final result = await service.lookup('9780140328721');

      expect(result.title, 'Book with unavailable cover');
      expect(result.author, 'A. Author');
      expect(result.plot, 'A full book description.');
      expect(result.coverBytes, isNull);
      service.close();
    });

    test('falls back to Open Library for book description', () async {
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response('{"totalItems":0}', 200);
          }
          return http.Response(
            jsonEncode({
              'ISBN:9780140328721': {
                'title': 'Fantastic Mr. Fox',
                'authors': [
                  {'name': 'Roald Dahl'},
                ],
                'publish_date': 'October 1, 1988',
                'number_of_pages': 96,
                'excerpts': [
                  {
                    'first_sentence': true,
                    'text': 'Down in the valley there were three farms.',
                  },
                ],
              },
            }),
            200,
          );
        }),
      );

      final result = await service.lookup('9780140328721');

      expect(result.title, 'Fantastic Mr. Fox');
      expect(result.author, 'Roald Dahl');
      expect(result.year, 1988);
      expect(result.pages, 96);
      expect(result.plot, 'Down in the valley there were three farms.');
      service.close();
    });

    test('uses IBS product metadata after Google Books rate limit', () async {
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response('Too Many Requests', 429);
          }
          if (request.url.host == 'www.ibs.it' &&
              request.url.path == '/search/') {
            expect(
              request.url.queryParameters['query'],
              '9788806226961',
            );
            return http.Response(
              '<a data-ean="9788806226961" '
              'href="/ernesto-libro-umberto-saba/e/9788806226961">'
              'Ernesto</a>',
              200,
            );
          }
          if (request.url.host == 'www.ibs.it' &&
              request.url.path.startsWith('/images/')) {
            return http.Response.bytes(
              [1, 2, 3],
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          if (request.url.host == 'www.ibs.it') {
            return http.Response(
              '''
              <script type="application/ld+json">
              {
                "@graph": [
                  {
                    "@type": "Book",
                    "name": "Ernesto",
                    "author": {"@type": "Person", "name": "Umberto Saba"},
                    "datePublished": "2015-03-23",
                    "description": "Sinossi recuperata dal catalogo IBS.",
                    "image": "https://www.ibs.it/images/9788806226961.jpg"
                  }
                ]
              }
              </script>
              ''',
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );

      final result = await service.lookup('9788806226961');

      expect(result.title, 'Ernesto');
      expect(result.author, 'Umberto Saba');
      expect(result.year, 2015);
      expect(result.plot, 'Sinossi recuperata dal catalogo IBS.');
      expect(result.coverBytes, [1, 2, 3]);
      expect(result.coverExtension, '.jpg');
      service.close();
    });

    test('uses NiceBooks metadata and cover after other catalogs miss',
        () async {
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response('Too Many Requests', 429);
          }
          if (request.url.host == 'www.ibs.it') {
            return http.Response('<html>No matching book</html>', 200);
          }
          if (request.url.host == 'nicebooks.com') {
            expect(request.url.path, '/it/search/isbn');
            expect(
              request.url.queryParameters['isbn'],
              '9788806226961',
            );
            expect(
              request.headers['X-Requested-With'],
              'XMLHttpRequest',
            );
            return http.Response(
              '''
              <div class="search-result-line">
                <div class="cover-container">
                  <img src="https://images.nicebooks.com/book.jpg?width=240&amp;quality=90">
                </div>
                <a href="/it/book/33749046-Ernesto" class="title">Ernesto</a>
                <div>di <a class="sublinks">Saba, Umberto</a></div>
                <div>23 Marzo 2015, <em>Edizione in brossura</em>, 100 pagine</div>
              </div>
              ''',
              200,
            );
          }
          if (request.url.host == 'images.nicebooks.com') {
            return http.Response.bytes(
              [1, 2, 3],
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          return http.Response('{}', 200);
        }),
      );

      final result = await service.lookup('9788806226961');

      expect(result.title, 'Ernesto');
      expect(result.author, 'Saba, Umberto');
      expect(result.year, 2015);
      expect(result.pages, 100);
      expect(result.coverBytes, [1, 2, 3]);
      expect(result.coverExtension, '.jpg');
      expect(result.plot, isNull);
      service.close();
    });

    test('continues to Open Library when NiceBooks returns a challenge page',
        () async {
      var niceBooksRequested = false;
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response('Too Many Requests', 429);
          }
          if (request.url.host == 'www.ibs.it') {
            return http.Response('<html>No matching book</html>', 200);
          }
          if (request.url.host == 'nicebooks.com') {
            niceBooksRequested = true;
            return http.Response(
              '<html><title>Just a moment...</title>Cloudflare</html>',
              200,
            );
          }
          if (request.url.path == '/api/books') {
            return http.Response(
              jsonEncode({
                'ISBN:9780140328721': {
                  'title': 'Fantastic Mr. Fox',
                  'authors': [
                    {'name': 'Roald Dahl'},
                  ],
                },
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );

      final result = await service.lookup('9780140328721');

      expect(niceBooksRequested, isTrue);
      expect(result.title, 'Fantastic Mr. Fox');
      expect(result.author, 'Roald Dahl');
      service.close();
    });

    test('falls back to Open Library when Google Books responds 429', () async {
      var openLibraryRequested = false;
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response('Too Many Requests', 429);
          }
          openLibraryRequested = true;
          return http.Response(
            jsonEncode({
              'ISBN:9780140328721': {
                'title': 'Fantastic Mr. Fox',
                'authors': [
                  {'name': 'Roald Dahl'},
                ],
              },
            }),
            200,
          );
        }),
      );

      final result = await service.lookup('9780140328721');

      expect(openLibraryRequested, isTrue);
      expect(result.title, 'Fantastic Mr. Fox');
      expect(result.author, 'Roald Dahl');
      service.close();
    });

    test('loads a full synopsis from the Open Library work record', () async {
      const synopsis =
          'Mr. Fox steals food to feed his family. The farmers try to capture '
          'him, but he leads the animals through tunnels to safety and food.';
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response('Too Many Requests', 429);
          }
          if (request.url.path == '/api/books') {
            return http.Response(
              jsonEncode({
                'ISBN:9780140328721': {
                  'title': 'Fantastic Mr. Fox',
                  'excerpts': [
                    {'first_sentence': true, 'text': 'Down in the valley.'},
                  ],
                },
              }),
              200,
            );
          }
          if (request.url.path == '/search.json') {
            return http.Response(
              jsonEncode({
                'docs': [
                  {
                    'key': '/works/OL45804W',
                    'title': 'Fantastic Mr Fox',
                    'author_name': ['Roald Dahl'],
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/works/OL45804W.json') {
            return http.Response(jsonEncode({'description': synopsis}), 200);
          }
          if (request.url.host == 'covers.openlibrary.org') {
            return http.Response('Not found', 404);
          }
          return http.Response('{}', 200);
        }),
      );

      final result = await service.lookup('9780140328721');

      expect(result.plot, synopsis);
      expect(result.author, 'Roald Dahl');
      service.close();
    });

    test('tries ISBN-10 when Google Books rate-limits an ISBN-13', () async {
      var isbn10Searched = false;
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response('Too Many Requests', 429);
          }
          if (request.url.path == '/api/books') {
            if (request.url.queryParameters['bibkeys'] == 'ISBN:0140328726') {
              isbn10Searched = true;
              return http.Response(
                jsonEncode({
                  'ISBN:0140328726': {
                    'title': 'Fantastic Mr. Fox',
                    'authors': [
                      {'name': 'Roald Dahl'},
                    ],
                  },
                }),
                200,
              );
            }
            return http.Response('{}', 200);
          }
          return http.Response('{}', 200);
        }),
      );

      final result = await service.lookup('9780140328721');

      expect(isbn10Searched, isTrue);
      expect(result.title, 'Fantastic Mr. Fox');
      expect(result.author, 'Roald Dahl');
      service.close();
    });

    test('keeps Open Library search metadata when work request fails',
        () async {
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response('Too Many Requests', 429);
          }
          if (request.url.path == '/api/books') {
            return http.Response('{}', 200);
          }
          if (request.url.path == '/search.json') {
            return http.Response(
              jsonEncode({
                'docs': [
                  {
                    'key': '/works/OL45804W',
                    'title': 'Fantastic Mr Fox',
                    'author_name': ['Roald Dahl'],
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/works/OL45804W.json') {
            throw http.ClientException('work endpoint is unavailable');
          }
          return http.Response('{}', 200);
        }),
      );

      final result = await service.lookup('9780140328721');

      expect(result.title, 'Fantastic Mr Fox');
      expect(result.author, 'Roald Dahl');
      service.close();
    });

    test('shows a useful message when 429 fallback has no matching book',
        () async {
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response('Too Many Requests', 429);
          }
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        service.lookup('9780140328721'),
        throwsA(
          predicate(
            (error) =>
                error.toString().contains('Google Books è temporaneamente') &&
                error.toString().contains('inserisci i dati'),
          ),
        ),
      );
      service.close();
    });

    test('uses Internet Archive to fill a missing plot automatically',
        () async {
      final service = IsbnLookupService(
        client: MockClient((request) async {
          if (request.url.host == 'www.googleapis.com') {
            return http.Response('Too Many Requests', 429);
          }
          if (request.url.host == 'openlibrary.org') {
            return http.Response(
              jsonEncode({
                'ISBN:9780140328721': <String, Object?>{},
              }),
              200,
            );
          }
          if (request.url.path == '/advancedsearch.php') {
            return http.Response(
              jsonEncode({
                'response': {
                  'docs': [
                    {
                      'identifier': 'archive-donation',
                      'title': 'Donation From Better World Books',
                    },
                    {
                      'identifier': 'fantastic-mr-fox',
                      'title': 'Fantastic Mr. Fox',
                      'creator': ['Roald Dahl'],
                      'description': [
                        'Three farmers try to get rid of a clever fox.',
                      ],
                      'year': 1988,
                      'subject': ['Children fiction'],
                    },
                  ],
                },
              }),
              200,
            );
          }
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );

      final result = await service.lookup('9780140328721');

      expect(result.title, 'Fantastic Mr. Fox');
      expect(result.author, 'Roald Dahl');
      expect(result.plot, 'Three farmers try to get rid of a clever fox.');
      expect(result.theme, 'Children fiction');
      expect(result.coverBytes, [1, 2, 3]);
      service.close();
    });

    test('rejects invalid ISBN without a network request', () async {
      var requests = 0;
      final service = IsbnLookupService(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        service.lookup('123'),
        throwsA(isA<FormatException>()),
      );
      expect(requests, 0);
      service.close();
    });

    test('shows NiceBooks ISBN suggestions for a mistyped code', () async {
      final service = IsbnLookupService(
        client: MockClient((request) async {
          expect(request.url.host, 'nicebooks.com');
          expect(
            request.url.queryParameters['isbn'],
            '9780140328722',
          );
          return http.Response(
            '''
            <div class="isbn-suggestions">
              <div class="isbn-lookup-suggestion" data-isbn="9780140328721"></div>
              <a href="/it/search/isbn?isbn=9780140328721">9780140328721</a>
            </div>
            ''',
            200,
          );
        }),
      );

      await expectLater(
        service.lookup('9780140328722'),
        throwsA(
          predicate(
            (error) =>
                error is FormatException &&
                error.message.contains('9780140328721') &&
                error.message.contains('NiceBooks suggerisce'),
          ),
        ),
      );
      service.close();
    });
  });
}
