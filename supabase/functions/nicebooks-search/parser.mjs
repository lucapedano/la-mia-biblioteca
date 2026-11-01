function decodeHtmlEntities(value) {
  const named = {
    amp: '&',
    apos: "'",
    eacute: 'é',
    egrave: 'è',
    gt: '>',
    hellip: '…',
    lt: '<',
    mdash: '—',
    nbsp: ' ',
    ndash: '–',
    ograve: 'ò',
    quot: '"',
    rsquo: '’',
    ugrave: 'ù',
  };
  return value.replace(
    /&(#x[\da-f]+|#\d+|[a-z][a-z\d]+);/gi,
    (entityText, entity) => {
      const lower = entity.toLowerCase();
      if (lower.startsWith('#x')) {
        const codePoint = Number.parseInt(lower.slice(2), 16);
        return codePoint <= 0x10ffff ? String.fromCodePoint(codePoint) : entityText;
      }
      if (lower.startsWith('#')) {
        const codePoint = Number.parseInt(lower.slice(1), 10);
        return codePoint <= 0x10ffff ? String.fromCodePoint(codePoint) : entityText;
      }
      return named[lower] ?? entityText;
    },
  );
}

function htmlText(value) {
  return decodeHtmlEntities(value.replace(/<[^>]*>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim();
}

function niceBooksCover(value) {
  try {
    const url = new URL(decodeHtmlEntities(value), 'https://nicebooks.com');
    return url.protocol === 'https:' && url.hostname === 'images.nicebooks.com'
      ? url.toString()
      : '';
  } catch {
    return '';
  }
}

export function parseNiceBooksHtml(html, isbn) {
  const suggestions = new Set();
  const suggestionPatterns = [
    /data-isbn=["'](\d{10,13})["']/gi,
    /\/search\/isbn\?isbn=(\d{10,13})/gi,
  ];
  for (const pattern of suggestionPatterns) {
    for (const match of html.matchAll(pattern)) {
      if (match[1] !== isbn) suggestions.add(match[1]);
    }
  }

  const resultMatch = /<div\b[^>]*class=["'][^"']*\bsearch-result-line\b[^"']*["'][^>]*>/i
    .exec(html);
  if (!resultMatch) return { book: null, suggestions: [...suggestions] };

  const afterResult = html.slice(resultMatch.index);
  const suggestionsMatch = /<[^>]*class=["'][^"']*\bisbn-suggestions\b[^"']*["'][^>]*>/i
    .exec(afterResult);
  const resultHtml = suggestionsMatch
    ? afterResult.slice(0, suggestionsMatch.index)
    : afterResult;
  const titleMatch = /<a\b([^>]*\bclass=["'][^"']*\btitle\b[^"']*["'][^>]*)>([\s\S]*?)<\/a>/i
    .exec(resultHtml);
  const title = titleMatch ? htmlText(titleMatch[2]) : '';
  if (!title) return { book: null, suggestions: [...suggestions] };

  const authorMatch = />\s*di\s*<a\b[^>]*\bclass=["'][^"']*\bsublinks\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i
    .exec(resultHtml);
  const imageMatch = /<img\b[^>]*\bsrc=["']([^"']+)["']/i.exec(resultHtml);
  const resultText = htmlText(resultHtml);
  const yearMatch = /\b(?:18|19|20)\d{2}\b/.exec(resultText);
  const pagesMatch = /\b(\d+)\s+pag(?:ine|ina)\b/i.exec(resultText);

  return {
    book: {
      title,
      author: authorMatch ? htmlText(authorMatch[1]) : '',
      year: yearMatch ? Number(yearMatch[0]) : null,
      pages: pagesMatch ? Number(pagesMatch[1]) : null,
      theme: '',
      isbn,
      coverUrl: imageMatch ? niceBooksCover(imageMatch[1]) : '',
      source: 'NiceBooks',
    },
    suggestions: [...suggestions],
  };
}
