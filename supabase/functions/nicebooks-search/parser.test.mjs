import assert from 'node:assert/strict';
import test from 'node:test';

import { parseNiceBooksHtml } from './parser.mjs';

test('parses NiceBooks ISBN metadata and a safe cover URL', () => {
  const result = parseNiceBooksHtml(
    `
      <div class="search-result-line">
        <img src="https://images.nicebooks.com/book.jpg?width=240&amp;quality=90">
        <a href="/it/book/33749046-Ernesto" class="title">Ernesto</a>
        <div>di <a class="sublinks">Saba, Umberto</a></div>
        <div>23 Marzo 2015, Edizione in brossura, 100 pagine</div>
      </div>
    `,
    '9788806226961',
  );

  assert.deepEqual(result, {
    book: {
      title: 'Ernesto',
      author: 'Saba, Umberto',
      year: 2015,
      pages: 100,
      theme: '',
      isbn: '9788806226961',
      coverUrl: 'https://images.nicebooks.com/book.jpg?width=240&quality=90',
      source: 'NiceBooks',
    },
    suggestions: [],
  });
});

test('returns corrected ISBN suggestions when no book result is present', () => {
  const result = parseNiceBooksHtml(
    '<div class="isbn-suggestions"><a href="/it/search/isbn?isbn=9788806226916">9788806226916</a></div>',
    '9788806226961',
  );

  assert.equal(result.book, null);
  assert.deepEqual(result.suggestions, ['9788806226916']);
});

test('rejects cover URLs outside NiceBooks image hosting', () => {
  const result = parseNiceBooksHtml(
    '<div class="search-result-line"><img src="https://example.com/cover.jpg"><a class="title">Libro</a></div>',
    '9788806226961',
  );

  assert.equal(result.book.coverUrl, '');
});
