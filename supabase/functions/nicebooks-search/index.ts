import { parseNiceBooksHtml } from './parser.mjs';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function normalizeIsbn(value: unknown): string | null {
  const isbn = String(value ?? '').replace(/[^0-9X]/gi, '').toUpperCase();
  return /^\d{9}[\dX]$/.test(isbn) || /^\d{13}$/.test(isbn) ? isbn : null;
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Metodo non supportato.' }, 405);
  }
  if (!request.headers.get('authorization')?.startsWith('Bearer ')) {
    return jsonResponse({ error: 'Accedi per cercare su NiceBooks.' }, 401);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: 'Richiesta JSON non valida.' }, 400);
  }
  if (!isRecord(payload)) {
    return jsonResponse({ error: 'Richiesta non valida.' }, 400);
  }

  const isbn = normalizeIsbn(payload.isbn);
  if (!isbn) {
    return jsonResponse({ error: 'Inserisci un ISBN-10 o ISBN-13 valido.' }, 400);
  }

  const url = new URL('/it/search/isbn', 'https://nicebooks.com');
  url.searchParams.set('isbn', isbn);
  try {
    const response = await fetch(url, {
      headers: {
        Accept: 'text/html',
        'Accept-Language': 'it-IT,it;q=0.9',
        Referer: 'https://nicebooks.com/it/search/isbn',
        'User-Agent': 'LaMiaBiblioteca/1.0 (ISBN catalog lookup)',
        'X-Requested-With': 'XMLHttpRequest',
      },
      signal: AbortSignal.timeout(12000),
    });
    if (!response.ok) {
      return jsonResponse(
        { error: `NiceBooks ha risposto con HTTP ${response.status}.` },
        502,
      );
    }

    const html = await response.text();
    if (!html.includes('search-result-line') &&
        /cloudflare|just a moment|challenge-platform/i.test(html)) {
      return jsonResponse(
        { error: 'NiceBooks ha richiesto una verifica; riprova più tardi.' },
        502,
      );
    }
    const result = parseNiceBooksHtml(html, isbn);
    return jsonResponse({
      books: result.book ? [result.book] : [],
      warnings: result.book || result.suggestions.length === 0
        ? []
        : [`NiceBooks suggerisce gli ISBN: ${result.suggestions.join(', ')}.`],
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: `Ricerca NiceBooks non disponibile: ${detail}` }, 502);
  }
});
