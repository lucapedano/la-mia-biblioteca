(() => {
  const config = window.BIBLIO_SUPABASE_CONFIG || {};
  const setupWarning = document.querySelector('#setup-warning');
  const loginView = document.querySelector('#login-view');
  const libraryView = document.querySelector('#library-view');
  const account = document.querySelector('#account');
  const loginMessage = document.querySelector('#login-message');
  const statusMessage = document.querySelector('#status');
  const grid = document.querySelector('#book-grid');
  const dialog = document.querySelector('#book-dialog');
  const themeColorDialog = document.querySelector('#theme-color-dialog');
  const themeColorTitle = document.querySelector('#theme-color-title');
  const themeColorInput = document.querySelector('#theme-color-value');
  const themeColorMessage = document.querySelector('#theme-color-message');
  const details = document.querySelector('#book-detail-content');
  const editBookForm = document.querySelector('#edit-book-form');
  const editBookMessage = document.querySelector('#edit-book-message');
  const backupForm = document.querySelector('#backup-form');
  const backupMessage = document.querySelector('#backup-message');
  const addBookDialog = document.querySelector('#add-book-dialog');
  const addBookForm = document.querySelector('#add-book-form');
  const addBookMessage = document.querySelector('#add-book-message');
  const catalogQuery = document.querySelector('#book-catalog-query');
  const catalogSearchButton = document.querySelector('#search-book-catalog');
  const catalogSearchMessage = document.querySelector('#catalog-search-message');
  const catalogSearchResults = document.querySelector('#catalog-search-results');
  const catalogSourceLinks = document.querySelector('#catalog-source-links');
  let catalogSearchRequestId = 0;
  const demoBanner = document.querySelector('#demo-banner');
  const statusLabels = {
    to_buy: 'Da acquistare',
    to_read: 'Da leggere',
    reading: 'In corso',
    read: 'Letto',
  };
  const demoBooks = [
    {
      id: 'demo-1', title: 'Il giardino delle storie', author: 'Anna Bellini',
      theme: 'Narrativa', year: 2021, pages: 286, status: 'reading',
      color: '#52745c', location: 'Scaffale A · 2', plot: 'Una bibliotecaria ritrova un quaderno che custodisce le storie degli abitanti del suo quartiere.',
      notes: 'Un libro delicato, da leggere con calma.',
    },
    {
      id: 'demo-2', title: 'Atlante delle piccole cose', author: 'Marco Riva',
      theme: 'Viaggi', year: 2019, pages: 214, status: 'read',
      color: '#bd7957', location: 'Scaffale B · 1', plot: 'Un viaggio attraverso luoghi quotidiani, incontri inattesi e paesaggi da riscoprire.',
    },
    {
      id: 'demo-3', title: 'La casa sul lago', author: 'Elena Moretti',
      theme: 'Giallo', year: 2023, pages: 352, status: 'to_read',
      color: '#596b87', location: 'Scaffale A · 3', plot: 'Al ritorno nel paese natale, una restauratrice si trova davanti a un mistero dimenticato.',
    },
    {
      id: 'demo-4', title: 'Appunti per domani', author: 'Luca Ferri',
      theme: 'Saggistica', year: 2020, pages: 178, status: 'to_read',
      color: '#ad9b5c', location: 'Scaffale C · 1', plot: 'Idee semplici e pratiche per costruire abitudini più consapevoli.',
    },
    {
      id: 'demo-5', title: 'Il tempo delle mappe', author: 'Sara Conti',
      theme: 'Avventura', year: 2018, pages: 304, status: 'read',
      color: '#986477', location: 'Scaffale B · 2', plot: 'Due sorelle seguono una raccolta di mappe alla ricerca di una storia di famiglia.',
    },
    {
      id: 'demo-6', title: 'Cucina di stagione', author: 'Paolo Neri',
      theme: 'Cucina', year: 2022, pages: 160, status: 'reading',
      color: '#638b7d', location: 'Scaffale cucina', plot: 'Ricette e appunti per valorizzare ingredienti semplici durante tutto l’anno.',
    },
    {
      id: 'demo-7', title: 'Il sentiero delle stelle', author: 'Giulia Serra',
      theme: 'Avventura', year: 2024, pages: 288, status: 'to_buy',
      color: '#7286a1', plot: 'Un viaggio da intraprendere tra mappe, incontri e luoghi sconosciuti.',
    },
  ];
  let client;
  let currentUser = null;
  let books = [];
  let demoMode = false;
  let libraryViewMode = 'themes';
  let loadingBooks = false;
  let activeBookId = null;
  let activeThemeForColor = null;
  let cardDrag = null;
  let coverRequestQueue = Promise.resolve();
  const signedCoverUrls = new Map();
  const pendingCoverUrls = new Map();
  const cloudConfigured = Boolean(
    config.url && config.anonKey &&
    !config.url.includes('YOUR_PROJECT') &&
    !config.anonKey.includes('YOUR_'),
  );

  const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
  const errorMessage = (error, fallback) => {
    const message = String(error?.message || '');
    if (/too many connections|remaining connection slots|max clients reached/i.test(message)) {
      return 'Supabase ha raggiunto temporaneamente il limite di connessioni. Attendi qualche minuto e riprova con Aggiorna.';
    }
    return message || fallback;
  };
  const formatStatus = (value) => statusLabels[value] || value || 'Da leggere';
  const bookColor = (value) => /^#[\da-f]{6}$/i.test(String(value || ''))
    ? String(value)
    : '#8D6E63';
  const contrastColor = (hex) => {
    const color = bookColor(hex);
    const red = Number.parseInt(color.slice(1, 3), 16);
    const green = Number.parseInt(color.slice(3, 5), 16);
    const blue = Number.parseInt(color.slice(5, 7), 16);
    return (0.299 * red + 0.587 * green + 0.114 * blue) / 255 > 0.6
      ? '#1C1C1E'
      : '#FFFFFF';
  };

  function getBookOrderKey() {
    const userId = currentUser?.id || (demoMode ? 'demo' : null);
    return userId ? `la-mia-biblioteca:book-order:${userId}` : null;
  }

  function getThemeOrderKey() {
    const userId = currentUser?.id || (demoMode ? 'demo' : null);
    return userId ? `la-mia-biblioteca:theme-order:${userId}` : null;
  }

  function getThemeColorKey() {
    const userId = currentUser?.id || (demoMode ? 'demo' : null);
    return userId ? `la-mia-biblioteca:theme-colors:${userId}` : null;
  }

  function readThemeColorOverrides() {
    const key = getThemeColorKey();
    if (!key) return {};
    try {
      const stored = localStorage.getItem(key);
      if (!stored) return {};
      const parsed = JSON.parse(stored);
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('Il formato dei colori salvati non è valido.');
      }
      for (const [theme, color] of Object.entries(parsed)) {
        if (!theme.trim() || !/^#[\da-f]{6}$/i.test(String(color))) {
          throw new Error('È presente un colore tematico non valido.');
        }
      }
      return parsed;
    } catch (error) {
      statusMessage.textContent =
        `Impossibile leggere i colori delle tematiche: ${error.message || String(error)}`;
      return null;
    }
  }

  function saveThemeColorOverride(theme, color) {
    const key = getThemeColorKey();
    if (!key) throw new Error('Accedi per salvare il colore della tematica.');
    const overrides = readThemeColorOverrides();
    if (overrides === null) {
      throw new Error('Correggi i colori salvati nel browser prima di modificarli.');
    }
    if (color === null) delete overrides[theme];
    else overrides[theme] = bookColor(color);
    try {
      if (Object.keys(overrides).length) {
        localStorage.setItem(key, JSON.stringify(overrides));
      } else {
        localStorage.removeItem(key);
      }
    } catch (error) {
      throw new Error(`Impossibile salvare il colore nel browser: ${error.message || String(error)}`);
    }
  }

  function themeLabelForBook(book) {
    return String(book.theme || '').trim() || 'Senza tematica';
  }

  function displayBookColor(book, overrides) {
    return bookColor(overrides?.[themeLabelForBook(book)] || book.color);
  }

  function setOrderHint() {
    const hint = document.querySelector('#order-hint');
    hint.hidden = libraryViewMode === 'latest' || libraryViewMode === 'purchase';
    hint.textContent = libraryViewMode === 'themes'
      ? 'Trascina un post-it tematico in una nuova posizione oppure usa le frecce. L’ordine è salvato in questo browser.'
      : 'Trascina i libri per riordinarli oppure usa le frecce sulla scheda. L’ordine è salvato in questo browser.';
  }

  function orderedBooks(source) {
    const key = getBookOrderKey();
    if (!key) return [...source];
    try {
      const saved = JSON.parse(localStorage.getItem(key) || '[]');
      if (!Array.isArray(saved)) return [...source];
      const order = new Map(saved.map((id, index) => [String(id), index]));
      return [...source].sort((first, second) =>
        (order.get(first.id) ?? Number.MAX_SAFE_INTEGER) -
        (order.get(second.id) ?? Number.MAX_SAFE_INTEGER),
      );
    } catch (error) {
      statusMessage.textContent = `Impossibile leggere l’ordine salvato: ${error.message}`;
      return [...source];
    }
  }

  function saveBookOrder() {
    const key = getBookOrderKey();
    if (!key) return false;
    try {
      localStorage.setItem(key, JSON.stringify(books.map((book) => book.id)));
      return true;
    } catch (error) {
      statusMessage.textContent = `Riordino non salvato in questo browser: ${error.message}`;
      return false;
    }
  }

  function moveBook(sourceId, targetId, after = false) {
    if (sourceId === targetId || libraryViewMode !== 'books') return;
    const sourceIndex = books.findIndex((book) => book.id === sourceId);
    const targetIndex = books.findIndex((book) => book.id === targetId);
    if (sourceIndex < 0 || targetIndex < 0) return;
    const [book] = books.splice(sourceIndex, 1);
    let insertAt = books.findIndex((item) => item.id === targetId);
    if (insertAt < 0) return;
    if (after) insertAt += 1;
    books.splice(insertAt, 0, book);
    const saved = saveBookOrder();
    renderBooks();
    if (saved) {
      statusMessage.textContent = 'Ordine dei post-it salvato in questo browser.';
    }
  }

  function moveBookBy(id, offset) {
    const displayedIds = [...grid.querySelectorAll('.book-card')].map((card) => card.dataset.id);
    const index = displayedIds.indexOf(id);
    const targetId = displayedIds[index + offset];
    if (index >= 0 && targetId) moveBook(id, targetId, offset > 0);
  }

  function orderedThemes(source) {
    const key = getThemeOrderKey();
    if (!key) return [...source];
    try {
      const saved = JSON.parse(localStorage.getItem(key) || '[]');
      if (!Array.isArray(saved)) return [...source];
      const order = new Map(saved.map((theme, index) => [String(theme), index]));
      return [...source].sort((first, second) =>
        (order.get(first.label) ?? Number.MAX_SAFE_INTEGER) -
        (order.get(second.label) ?? Number.MAX_SAFE_INTEGER),
      );
    } catch (error) {
      statusMessage.textContent = `Impossibile leggere l’ordine delle tematiche: ${error.message}`;
      return [...source];
    }
  }

  function saveThemeOrder(labels) {
    const key = getThemeOrderKey();
    if (!key) return false;
    try {
      const saved = JSON.parse(localStorage.getItem(key) || '[]');
      const remaining = Array.isArray(saved)
        ? saved.filter((label) => !labels.includes(String(label))).map(String)
        : [];
      localStorage.setItem(key, JSON.stringify([...labels, ...remaining]));
      return true;
    } catch (error) {
      statusMessage.textContent = `Ordine delle tematiche non salvato in questo browser: ${error.message}`;
      return false;
    }
  }

  function moveTheme(sourceLabel, targetLabel, after = false) {
    if (sourceLabel === targetLabel || libraryViewMode !== 'themes') return;
    const displayed = [...grid.querySelectorAll('.theme-card')]
      .map((card) => card.dataset.theme);
    const sourceIndex = displayed.indexOf(sourceLabel);
    const targetIndex = displayed.indexOf(targetLabel);
    if (sourceIndex < 0 || targetIndex < 0) return;
    displayed.splice(sourceIndex, 1);
    let insertAt = displayed.indexOf(targetLabel);
    if (after) insertAt += 1;
    displayed.splice(insertAt, 0, sourceLabel);
    if (saveThemeOrder(displayed)) {
      renderBooks();
      statusMessage.textContent = 'Ordine delle tematiche salvato in questo browser.';
    }
  }

  function moveThemeBy(label, offset) {
    const displayed = [...grid.querySelectorAll('.theme-card')]
      .map((card) => card.dataset.theme);
    const index = displayed.indexOf(label);
    if (index < 0 || displayed.length < 2) return;
    const nextIndex = index + offset;
    const target = displayed[(nextIndex + displayed.length) % displayed.length];
    const wrapped = nextIndex < 0 || nextIndex >= displayed.length;
    moveTheme(label, target, wrapped ? offset < 0 : offset > 0);
  }

  function cardAtPoint(kind, x, y) {
    const gridBounds = grid.getBoundingClientRect();
    if (x < gridBounds.left || x > gridBounds.right ||
        y < gridBounds.top || y > gridBounds.bottom) return null;
    const selector = kind === 'theme' ? '.theme-card' : '.book-card';
    const cards = [...grid.querySelectorAll(selector)];
    const containing = cards.find((card) => {
      const bounds = card.getBoundingClientRect();
      return x >= bounds.left && x <= bounds.right &&
        y >= bounds.top && y <= bounds.bottom;
    });
    if (containing) return containing;
    return cards.reduce((nearest, card) => {
      const bounds = card.getBoundingClientRect();
      const dx = Math.max(bounds.left - x, 0, x - bounds.right);
      const dy = Math.max(bounds.top - y, 0, y - bounds.bottom);
      const distance = dx * dx + dy * dy;
      return !nearest || distance < nearest.distance
        ? { card, distance }
        : nearest;
    }, null)?.card || null;
  }

  grid.addEventListener('pointerdown', (event) => {
    if (event.target.closest('.move-theme-button, .move-book-button')) return;
    const themeCard = event.target.closest('.theme-card');
    const bookCard = event.target.closest('.book-card');
    const kind = themeCard ? 'theme' : bookCard ? 'book' : null;
    const card = themeCard || bookCard;
    if (!card || event.button !== 0 ||
        (kind === 'theme' && libraryViewMode !== 'themes') ||
        (kind === 'book' && libraryViewMode !== 'books')) return;
    cardDrag = {
      kind,
      pointerId: event.pointerId,
      source: kind === 'theme' ? card.dataset.theme : card.dataset.id,
      startX: event.clientX,
      startY: event.clientY,
      active: false,
    };
  });
  window.addEventListener('pointermove', (event) => {
    if (!cardDrag || event.pointerId !== cardDrag.pointerId) return;
    if (!cardDrag.active &&
        Math.hypot(event.clientX - cardDrag.startX, event.clientY - cardDrag.startY) >= 6) {
      cardDrag.active = true;
      cardAtPoint(cardDrag.kind, cardDrag.startX, cardDrag.startY)
        ?.classList.add('is-dragging');
    }
    if (!cardDrag.active) return;
    event.preventDefault();
    grid.querySelectorAll('.is-drop-target')
      .forEach((card) => card.classList.remove('is-drop-target'));
    const target = cardAtPoint(cardDrag.kind, event.clientX, event.clientY);
    const targetId = cardDrag.kind === 'theme' ? target?.dataset.theme : target?.dataset.id;
    if (target && targetId !== cardDrag.source) {
      target.classList.add('is-drop-target');
    }
  });
  window.addEventListener('pointerup', (event) => {
    if (!cardDrag || event.pointerId !== cardDrag.pointerId) return;
    const drag = cardDrag;
    const target = drag.active ? cardAtPoint(drag.kind, event.clientX, event.clientY) : null;
    const bounds = target?.getBoundingClientRect();
    const after = bounds && event.clientY >= bounds.top + bounds.height / 2;
    cardDrag = null;
    grid.querySelectorAll('.is-dragging, .is-drop-target')
      .forEach((card) => card.classList.remove('is-dragging', 'is-drop-target'));
    if (!target) return;
    if (drag.kind === 'theme') {
      if (target.dataset.theme !== drag.source) {
        moveTheme(drag.source, target.dataset.theme, after);
      }
    } else if (target.dataset.id !== drag.source) {
      moveBook(drag.source, target.dataset.id, after);
    }
  });
  window.addEventListener('pointercancel', (event) => {
    if (!cardDrag || event.pointerId !== cardDrag.pointerId) return;
    cardDrag = null;
    grid.querySelectorAll('.is-dragging, .is-drop-target')
      .forEach((card) => card.classList.remove('is-dragging', 'is-drop-target'));
  });

  async function coverUrl(book) {
    if (book.cover_url?.startsWith('http')) return book.cover_url;
    if (!book.cover_path) return '';
    const cached = signedCoverUrls.get(book.cover_path);
    if (cached && cached.expiresAt > Date.now()) return cached.url;
    const pending = pendingCoverUrls.get(book.cover_path);
    if (pending) return pending;

    const request = coverRequestQueue.then(async () => {
      const { data, error } = await client.storage.from('book-covers')
        .createSignedUrl(book.cover_path, 3600);
      if (error) throw error;
      signedCoverUrls.set(book.cover_path, {
        url: data.signedUrl,
        expiresAt: Date.now() + 55 * 60 * 1000,
      });
      return data.signedUrl;
    });
    coverRequestQueue = request.catch(() => {});
    pendingCoverUrls.set(book.cover_path, request);
    try {
      return await request;
    } finally {
      pendingCoverUrls.delete(book.cover_path);
    }
  }

  function showCoverError(book, error) {
    statusMessage.textContent =
      `Libro caricato; copertina non disponibile per "${book.title}": ${errorMessage(error, 'riprova più tardi.')}`;
  }

  async function loadBookCover(book, card) {
    try {
      const url = await coverUrl(book);
      if (!url) return;
      book.displayCover = url;
      if (card?.isConnected) {
        const cover = card.querySelector('.cover');
        const image = document.createElement('img');
        image.src = url;
        image.alt = `Copertina di ${book.title}`;
        cover.replaceChildren(image);
      }
      if (activeBookId === book.id && dialog.open &&
          !details.querySelector('.detail-cover')) {
        const image = document.createElement('img');
        image.className = 'detail-cover';
        image.src = url;
        image.alt = `Copertina di ${book.title}`;
        details.prepend(image);
      }
    } catch (error) {
      showCoverError(book, error);
    }
  }

  const coverObserver = 'IntersectionObserver' in window
    ? new IntersectionObserver((entries, observer) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        observer.unobserve(entry.target);
        const book = books.find((item) => item.id === entry.target.dataset.id);
        if (book?.cover_path && !book.displayCover) {
          void loadBookCover(book, entry.target);
        }
      }
    }, { rootMargin: '120px' })
    : null;

  function renderThemeOptions() {
    const selectedTheme = document.querySelector('#theme-filter').value;
    const themes = [...new Set(
      books.map((book) => String(book.theme || '').trim()).filter(Boolean),
    )].sort((first, second) => first.localeCompare(second, 'it'));
    const options = [
      '<option value="">Tutte le tematiche</option>',
      ...themes.map((theme) =>
        `<option value="${escapeHtml(theme)}">${escapeHtml(theme)}</option>`,
      ),
    ];
    document.querySelector('#theme-filter').innerHTML = options.join('');
    if (themes.includes(selectedTheme)) {
      document.querySelector('#theme-filter').value = selectedTheme;
    }
    document.querySelector('#theme-options').innerHTML = themes
      .map((theme) => `<option value="${escapeHtml(theme)}"></option>`)
      .join('');
  }

  function isNewBook(book) {
    const created = Date.parse(book.created_at || '');
    const age = Date.now() - created;
    return Number.isFinite(created) && age >= 0 && age < 24 * 60 * 60 * 1000;
  }

  function renderLatestNotice() {
    const notice = document.querySelector('#latest-notice');
    const newCount = books.filter(isNewBook).length;
    notice.hidden = newCount === 0;
    notice.textContent = newCount ? `Nuovi ${newCount}` : 'Nuovi';
    document.querySelector('#view-latest').classList.toggle('has-new', newCount > 0);
  }

  function showScreen(user) {
    currentUser = user || null;
    const signedIn = Boolean(user);
    loginView.hidden = signedIn;
    libraryView.hidden = !signedIn;
    account.hidden = !signedIn;
    demoBanner.hidden = !demoMode;
    if (user) document.querySelector('#account-email').textContent = user.email || '';
  }

  function bookIsbnKey(value) {
    return String(value || '').replace(/[^\dX]/gi, '').toUpperCase();
  }

  function sameBookForEntry(existing, incoming) {
    const existingIsbn = bookIsbnKey(existing.isbn);
    const incomingIsbn = bookIsbnKey(incoming.isbn);
    if (existingIsbn && incomingIsbn && existingIsbn === incomingIsbn) return true;

    const normalizeText = (value) => String(value || '')
      .trim()
      .replace(/\s+/g, ' ')
      .toLocaleLowerCase('it');
    if (normalizeText(existing.title) !== normalizeText(incoming.title) ||
        normalizeText(existing.author) !== normalizeText(incoming.author)) return false;
    if (existingIsbn && incomingIsbn && existingIsbn !== incomingIsbn) return false;
    if (existing.year && incoming.year && Number(existing.year) !== Number(incoming.year)) {
      return false;
    }
    if (existing.pages && incoming.pages && Number(existing.pages) !== Number(incoming.pages)) {
      return false;
    }
    return true;
  }

  async function addBook(event) {
    event.preventDefault();
    if (demoMode || !currentUser) {
      addBookMessage.textContent = 'Accedi al tuo account per aggiungere libri alla libreria.';
      return;
    }

    const formData = new FormData(addBookForm);
    const title = String(formData.get('title') || '').trim();
    const author = String(formData.get('author') || '').trim();
    const theme = String(formData.get('theme') || '').trim();
    if (!title || !author || !theme) {
      addBookMessage.textContent = 'Titolo, autore e tematica sono obbligatori.';
      return;
    }

    const draft = {
      title,
      author,
      year: formData.get('year') ? Number(formData.get('year')) : null,
      pages: formData.get('pages') ? Number(formData.get('pages')) : null,
      isbn: String(formData.get('isbn') || '').trim() || null,
    };
    const duplicate = books.find((book) => sameBookForEntry(book, draft));
    if (duplicate) {
      addBookMessage.textContent =
        `Doppione: "${duplicate.title}" di ${duplicate.author} è già presente. Il libro non è stato aggiunto.`;
      return;
    }

    const saveButton = document.querySelector('#save-book');
    saveButton.disabled = true;
    addBookMessage.textContent = '';
    const now = new Date().toISOString();
    const book = {
      id: crypto.randomUUID(),
      user_id: currentUser.id,
      title,
      author,
      theme,
      year: draft.year,
      pages: draft.pages,
      status: String(formData.get('status') || 'to_read'),
      color: bookColor(formData.get('color')),
      location: String(formData.get('location') || '').trim() || null,
      isbn: draft.isbn,
      cover_url: String(formData.get('cover_url') || '').trim() || null,
      plot: String(formData.get('plot') || '').trim() || null,
      notes: String(formData.get('notes') || '').trim() || null,
      cover_path: null,
      created_at: now,
      updated_at: now,
      deleted_at: null,
    };

    try {
      const { error } = await client.from('books').insert(book);
      if (error) throw error;
      addBookForm.reset();
      addBookDialog.close();
      await loadBooks();
    } catch (error) {
      addBookMessage.textContent = errorMessage(error, 'Impossibile salvare il libro.');
    } finally {
      saveButton.disabled = false;
    }
  }

  function catalogIsbn(value) {
    const compact = String(value || '').replace(/[^\dX]/gi, '').toUpperCase();
    return /^\d{9}[\dX]$/.test(compact) || /^\d{13}$/.test(compact)
      ? compact
      : null;
  }

  function catalogSearchUrl(site, query) {
    const isbn = catalogIsbn(query);
    const searchTerm = isbn || query.trim();
    if (site === 'anobii') {
      return `https://www.anobii.com/it/search?query=${encodeURIComponent(searchTerm)}`;
    }
    if (site === 'nicebooks') {
      return `https://nicebooks.com/it/search/isbn?isbn=${encodeURIComponent(isbn)}`;
    }
    const params = new URLSearchParams({
      currency: 'EUR',
      destination: 'it',
    });
    params.set(isbn ? 'isbn' : 'title', searchTerm);
    return `https://www.bookfinder.com/search/?${params.toString()}`;
  }

  function renderCatalogSourceLinks(query) {
    if (!query) {
      catalogSourceLinks.innerHTML = '';
      return;
    }
    const sources = [
      { key: 'anobii', label: 'Anobii' },
      { key: 'bookfinder', label: 'BookFinder' },
      ...(catalogIsbn(query) ? [{ key: 'nicebooks', label: 'NiceBooks' }] : []),
    ];
    catalogSourceLinks.innerHTML = sources.map((site) => `
      <a class="button button-quiet" href="${escapeHtml(catalogSearchUrl(site.key, query))}"
        target="_blank" rel="noopener noreferrer">Cerca su ${site.label}</a>
    `).join('');
  }

  function catalogBookIsbn(values) {
    if (!Array.isArray(values)) return null;
    const candidates = values
      .map((item) => catalogIsbn(item?.identifier ?? item))
      .filter(Boolean);
    return candidates.find((isbn) => isbn.length === 13) || candidates[0] || null;
  }

  function catalogCoverUrl(value) {
    const coverUrl = String(value || '').trim();
    if (!/^https?:\/\//i.test(coverUrl)) return '';
    return coverUrl.replace(/^http:\/\//i, 'https://');
  }

  async function searchGoogleBooks(query, isbn) {
    const params = new URLSearchParams({
      q: isbn ? `isbn:${isbn}` : `intitle:${query}`,
      maxResults: '8',
      printType: 'books',
    });
    const response = await fetch(`https://www.googleapis.com/books/v1/volumes?${params}`);
    if (!response.ok) throw new Error(`Google Books (HTTP ${response.status})`);
    const body = await response.json();
    const items = Array.isArray(body.items) ? body.items : [];
    return items.map((item) => {
      const info = item.volumeInfo || {};
      const identifiers = Array.isArray(info.industryIdentifiers)
        ? info.industryIdentifiers
        : [];
      const publishedYear = String(info.publishedDate || '').match(/\b\d{4}\b/)?.[0];
      const imageLinks = info.imageLinks || {};
      return {
        title: String(info.title || '').trim(),
        author: Array.isArray(info.authors) ? info.authors.join(', ') : '',
        year: publishedYear ? Number(publishedYear) : null,
        pages: Number.isInteger(info.pageCount) ? info.pageCount : null,
        theme: Array.isArray(info.categories) ? String(info.categories[0] || '') : '',
        isbn: catalogBookIsbn(identifiers),
        coverUrl: catalogCoverUrl(imageLinks.thumbnail || imageLinks.smallThumbnail),
        source: 'Google Books',
      };
    }).filter((book) => book.title);
  }

  async function searchOpenLibrary(query, isbn) {
    const params = new URLSearchParams({
      fields: 'title,author_name,first_publish_year,number_of_pages_median,cover_i,isbn',
      limit: '8',
    });
    params.set(isbn ? 'isbn' : 'title', isbn || query);
    const response = await fetch(`https://openlibrary.org/search.json?${params}`);
    if (!response.ok) throw new Error(`Open Library (HTTP ${response.status})`);
    const body = await response.json();
    const docs = Array.isArray(body.docs) ? body.docs : [];
    return docs.map((doc) => {
      const coverId = Number(doc.cover_i);
      return {
        title: String(doc.title || '').trim(),
        author: Array.isArray(doc.author_name) ? doc.author_name.join(', ') : '',
        year: Number.isInteger(doc.first_publish_year) ? doc.first_publish_year : null,
        pages: Number.isInteger(doc.number_of_pages_median)
          ? doc.number_of_pages_median
          : null,
        theme: '',
        isbn: catalogBookIsbn(doc.isbn),
        coverUrl: Number.isInteger(coverId) && coverId > 0
          ? `https://covers.openlibrary.org/b/id/${coverId}-M.jpg?default=false`
          : '',
        source: 'Open Library',
      };
    }).filter((book) => book.title);
  }

  async function searchNiceBooks(isbn) {
    const { data, error } = await client.functions.invoke('nicebooks-search', {
      body: { isbn },
    });
    if (error) throw new Error(`NiceBooks: ${error.message || String(error)}`);
    if (!data || !Array.isArray(data.books)) {
      throw new Error('NiceBooks ha restituito una risposta non valida.');
    }
    if (!data.books.length && data.warnings?.length) {
      throw new Error(data.warnings.join(' '));
    }
    return data.books.map((book) => ({
      title: String(book.title || '').trim(),
      author: String(book.author || '').trim(),
      year: Number.isInteger(book.year) ? book.year : null,
      pages: Number.isInteger(book.pages) ? book.pages : null,
      theme: String(book.theme || ''),
      isbn: catalogIsbn(book.isbn) || isbn,
      coverUrl: catalogCoverUrl(book.coverUrl),
      source: 'NiceBooks',
    })).filter((book) => book.title);
  }

  function mergeCatalogBooks(books) {
    const unique = [];
    for (const book of books) {
      const existingIndex = unique.findIndex((existing) => {
        if (existing.isbn && book.isbn) return existing.isbn === book.isbn;
        return existing.title.toLocaleLowerCase() === book.title.toLocaleLowerCase() &&
          existing.author.toLocaleLowerCase() === book.author.toLocaleLowerCase();
      });
      if (existingIndex < 0) {
        unique.push(book);
        continue;
      }
      const existing = unique[existingIndex];
      unique[existingIndex] = Object.fromEntries(
        Object.keys(existing).map((key) => [key, existing[key] || book[key]]),
      );
    }
    return unique;
  }

  function importCatalogBook(book) {
    const fields = {
      title: book.title,
      author: book.author,
      theme: book.theme,
      year: book.year,
      pages: book.pages,
      isbn: book.isbn || catalogIsbn(catalogQuery.value),
      cover_url: book.coverUrl,
      status: 'to_buy',
    };
    for (const [name, value] of Object.entries(fields)) {
      if (value === null || value === undefined || value === '') continue;
      addBookForm.elements.namedItem(name).value = String(value);
    }
    catalogSearchMessage.textContent =
      'Dati inseriti nella scheda. Controlla la tematica e salva il libro.';
  }

  function resetCatalogSearch() {
    catalogSearchRequestId++;
    catalogQuery.value = '';
    catalogSearchMessage.textContent = '';
    catalogSearchResults.innerHTML = '';
    catalogSourceLinks.innerHTML = '';
    catalogSearchButton.disabled = false;
  }

  async function searchBookCatalogs() {
    const query = catalogQuery.value.trim();
    if (!query) {
      catalogSearchMessage.textContent = 'Inserisci un titolo o un ISBN.';
      catalogQuery.focus();
      return;
    }

    const isbn = catalogIsbn(query);
    const requestId = ++catalogSearchRequestId;
    catalogSearchButton.disabled = true;
    catalogSearchMessage.textContent = 'Ricerca nei cataloghi…';
    catalogSearchResults.innerHTML = '';
    renderCatalogSourceLinks(query);
    try {
      const responses = await Promise.allSettled([
        searchGoogleBooks(query, isbn),
        searchOpenLibrary(query, isbn),
        ...(isbn ? [searchNiceBooks(isbn)] : []),
      ]);
      if (requestId !== catalogSearchRequestId) return;
      const books = mergeCatalogBooks(
        responses
          .filter((response) => response.status === 'fulfilled')
          .flatMap((response) => response.value),
      );
      const warnings = responses
        .filter((response) => response.status === 'rejected')
        .map((response) => response.reason.message || String(response.reason));
      catalogSearchResults.innerHTML = books.map((book, index) => {
        const subtitle = [book.source, book.author, book.year, book.isbn]
          .filter(Boolean)
          .map(escapeHtml)
          .join(' · ');
        return `<article class="catalog-search-result">
          ${book.coverUrl
            ? `<img class="catalog-search-cover" src="${escapeHtml(book.coverUrl)}" alt="">`
            : ''}
          <div class="catalog-search-result-info">
            <strong>${escapeHtml(book.title)}</strong>
            ${subtitle ? `<span>${subtitle}</span>` : ''}
          </div>
          <button class="button button-primary" type="button" data-import-catalog="${index}">Importa</button>
        </article>`;
      }).join('');
      catalogSearchResults.querySelectorAll('[data-import-catalog]').forEach((button) => {
        button.addEventListener('click', () => {
          importCatalogBook(books[Number(button.dataset.importCatalog)]);
        });
      });
      if (books.length) {
        catalogSearchMessage.textContent = warnings.length
          ? `Risultati parziali. ${warnings.join(' ')}`
          : `${books.length} risultati. Seleziona un libro per compilare la scheda.`;
      } else {
        catalogSearchMessage.textContent = warnings.length
          ? `Ricerca non disponibile: ${warnings.join(' ')}`
          : 'Nessun libro trovato nei cataloghi. Puoi provare su Anobii, BookFinder o NiceBooks.';
      }
    } catch (error) {
      if (requestId === catalogSearchRequestId) {
        catalogSearchMessage.textContent =
          `Ricerca non riuscita: ${error.message || String(error)}`;
      }
    } finally {
      if (requestId === catalogSearchRequestId) {
        catalogSearchButton.disabled = false;
      }
    }
  }

  function enterDemo() {
    demoMode = true;
    setOrderHint();
    books = demoBooks.map((book, index) => ({
      ...book,
      created_at: new Date(Date.now() - index * 60 * 60 * 1000).toISOString(),
      displayCover: '',
    }));
    setupWarning.hidden = true;
    renderThemeOptions();
    renderLatestNotice();
    document.querySelector('#library-tagline').textContent =
      'Esplora una libreria di esempio: ricerca, filtri e schede libro sono interattivi.';
    showScreen({ email: 'Demo locale' });
    renderStats();
    renderBooks();
    statusMessage.textContent = '7 libri di esempio · prova ricerca, filtri e dettagli.';
  }

  async function loadBooks() {
    if (loadingBooks) return;
    loadingBooks = true;
    statusMessage.textContent = 'Caricamento della libreria…';
    try {
      const { data, error } = await client.from('books')
        .select('*')
        .is('deleted_at', null)
        .order('title', { ascending: true });
      if (error) throw error;
      books = (data || []).map((book) => ({
        ...book,
        displayCover: book.cover_url?.startsWith('http') ? book.cover_url : '',
      }));
      setOrderHint();
      renderThemeOptions();
      renderStats();
      renderLatestNotice();
      renderBooks();
      statusMessage.textContent = books.length
        ? `${books.length} ${books.length === 1 ? 'libro nella libreria' : 'libri nella libreria'}`
        : 'La libreria è vuota. Importa un backup dall’app dopo aver effettuato l’accesso.';
    } finally {
      loadingBooks = false;
    }
  }

  function renderStats() {
    const stats = [
      ['Totale libri', books.length],
      ['Da acquistare', books.filter((book) => book.status === 'to_buy').length],
      ['Da leggere', books.filter((book) => book.status === 'to_read').length],
      ['In lettura', books.filter((book) => book.status === 'reading').length],
      ['Letti', books.filter((book) => book.status === 'read').length],
    ];
    document.querySelector('#stats').innerHTML = stats.map(([label, value]) =>
      `<article class="stat"><span class="stat-value">${value}</span><div class="stat-label">${label}</div></article>`,
    ).join('');
  }

  function renderBooks() {
    const query = document.querySelector('#search').value.trim().toLocaleLowerCase('it');
    const status = libraryViewMode === 'purchase'
      ? 'to_buy'
      : document.querySelector('#status-filter').value;
    const theme = document.querySelector('#theme-filter').value;
    const visible = books.filter((book) => {
      const matchesText = ['title', 'author', 'theme', 'plot', 'notes', 'isbn']
        .some((field) => String(book[field] || '').toLocaleLowerCase('it').includes(query));
      return matchesText &&
        (!status || book.status === status) &&
        (!theme || String(book.theme || '').trim() === theme);
    });
    if (!visible.length) {
      grid.innerHTML = libraryViewMode === 'purchase'
        ? '<div class="empty">Nessun libro da acquistare. Aggiungine uno con “Aggiungi libro”.</div>'
        : '<div class="empty">Nessun libro trovato con questi filtri.</div>';
      return;
    }
    if (libraryViewMode === 'themes') {
      renderThemeGroups(visible);
      return;
    }

    const displayedBooks = libraryViewMode === 'latest'
      ? [...visible]
        .sort((first, second) =>
          (Date.parse(second.created_at || '') || 0) -
          (Date.parse(first.created_at || '') || 0),
        )
        .slice(0, 10)
      : orderedBooks(visible);
    renderBookCards(displayedBooks);
  }

  function renderBookCards(displayedBooks) {
    const themeColors = readThemeColorOverrides();
    grid.innerHTML = displayedBooks.map((book) => `
      <article class="book-card" data-id="${escapeHtml(book.id)}" tabindex="0" aria-label="Apri la scheda di ${escapeHtml(book.title)}">
        ${libraryViewMode === 'books' ? `<div class="book-card-tools">
          <span class="drag-handle" aria-label="Trascina per spostare ${escapeHtml(book.title)}" title="Trascina per spostare">⠿</span>
          <button class="move-book-button" type="button" data-move="-1" aria-label="Sposta ${escapeHtml(book.title)} prima">↑</button>
          <button class="move-book-button" type="button" data-move="1" aria-label="Sposta ${escapeHtml(book.title)} dopo">↓</button>
        </div>` : ''}
        <div class="cover" style="--cover:${displayBookColor(book, themeColors)}">
          ${book.displayCover
            ? `<img src="${escapeHtml(book.displayCover)}" alt="Copertina di ${escapeHtml(book.title)}">`
            : '<span class="cover-symbol" aria-hidden="true">▤</span>'}
        </div>
        <div class="book-info" style="--book-color:${displayBookColor(book, themeColors)}">
          <h2 class="book-title" title="${escapeHtml(book.title)}">
            ${escapeHtml(book.title)}${isNewBook(book) ? '<span class="new-book-mark">Nuovo</span>' : ''}
          </h2>
          <p class="book-author">${escapeHtml(book.author)}</p>
          <div class="book-meta"><span>${escapeHtml(book.theme || 'Senza categoria')}</span><span class="pill">${escapeHtml(formatStatus(book.status))}</span></div>
        </div>
      </article>`,
    ).join('');
    grid.querySelectorAll('.book-card').forEach((card) => {
      const open = (event) => {
        if (event.target.closest('.book-card-tools')) return;
        showBook(books.find((book) => book.id === card.dataset.id));
      };
      card.addEventListener('click', open);
      card.addEventListener('keydown', (event) => {
        if (event.target !== card) return;
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          open(event);
        }
      });
      const cardIndex = displayedBooks.findIndex((book) => book.id === card.dataset.id);
      card.querySelectorAll('.move-book-button').forEach((button) => {
        const offset = Number(button.dataset.move);
        button.disabled = libraryViewMode !== 'books' ||
          cardIndex < 0 || !displayedBooks[cardIndex + offset];
        button.addEventListener('click', (event) => {
          event.stopPropagation();
          moveBookBy(card.dataset.id, offset);
        });
      });
      const book = books.find((item) => item.id === card.dataset.id);
      if (book?.cover_path && !book.displayCover) {
        if (coverObserver) coverObserver.observe(card);
        else void loadBookCover(book, card);
      }
    });
  }

  function openThemeColorDialog(theme) {
    if (demoMode) return;
    const overrides = readThemeColorOverrides();
    const firstBook = books.find((book) => themeLabelForBook(book) === theme);
    themeColorTitle.textContent = `Colore tematica: ${theme}`;
    themeColorMessage.textContent = '';
    themeColorInput.value = bookColor(overrides?.[theme] || firstBook?.color);
    activeThemeForColor = theme;
    themeColorDialog.showModal();
  }

  function renderThemeGroups(visibleBooks) {
    const groups = new Map();
    const themeColors = readThemeColorOverrides();
    visibleBooks.forEach((book) => {
      const label = String(book.theme || '').trim() || 'Senza tematica';
      if (!groups.has(label)) {
        groups.set(label, {
          label,
          color: bookColor(themeColors?.[label] || book.color),
          count: 0,
        });
      }
      groups.get(label).count += 1;
    });
    const sortedGroups = orderedThemes([...groups.values()].sort((first, second) =>
      second.count - first.count || first.label.localeCompare(second.label, 'it'),
    ));

    grid.innerHTML = sortedGroups.map((group, index) => `
      <article class="theme-card" data-theme="${escapeHtml(group.label)}">
        <span class="theme-fold" aria-hidden="true"></span>
        <div class="theme-card-tools">
          <span class="drag-handle" title="Tieni premuto e trascina per spostare" aria-label="Tieni premuto e trascina per spostare ${escapeHtml(group.label)}">⠿</span>
          <button class="move-theme-button" type="button" data-move="-1" aria-label="Sposta ${escapeHtml(group.label)} prima" ${sortedGroups.length < 2 ? 'disabled title="Serve un’altra tematica per riordinare"' : ''}>↑</button>
          <button class="move-theme-button" type="button" data-move="1" aria-label="Sposta ${escapeHtml(group.label)} dopo" ${sortedGroups.length < 2 ? 'disabled title="Serve un’altra tematica per riordinare"' : ''}>↓</button>
          ${demoMode ? '' : `<button class="theme-color-button" type="button" aria-label="Cambia colore tematica ${escapeHtml(group.label)}" title="Cambia colore tematica">🎨</button>`}
        </div>
        <button class="theme-open" type="button" data-theme="${escapeHtml(group.label)}"
          style="--theme-color:${group.color};--theme-text:${contrastColor(group.color)}">
          <span class="theme-label">${escapeHtml(group.label)}</span>
          <span class="theme-count">${group.count} ${group.count === 1 ? 'libro' : 'libri'}</span>
        </button>
      </article>`).join('');
    grid.querySelectorAll('.move-theme-button').forEach((button) => {
      button.addEventListener('click', (event) => {
        event.stopPropagation();
        const label = button.closest('.theme-card').dataset.theme;
        moveThemeBy(label, Number(button.dataset.move));
      });
    });
    grid.querySelectorAll('.theme-color-button').forEach((button) => {
      button.addEventListener('click', (event) => {
        event.stopPropagation();
        openThemeColorDialog(button.closest('.theme-card').dataset.theme);
      });
    });
    grid.querySelectorAll('.theme-open').forEach((button) => {
      button.addEventListener('click', () => {
        document.querySelector('#theme-filter').value = button.dataset.theme;
        setLibraryViewMode('books');
        renderBooks();
      });
    });
  }

  function setLibraryViewMode(mode) {
    const previousMode = libraryViewMode;
    libraryViewMode = mode;
    setOrderHint();
    const statusFilter = document.querySelector('#status-filter');
    statusFilter.disabled = mode === 'purchase';
    if (mode === 'purchase') {
      statusFilter.value = 'to_buy';
    } else if (previousMode === 'purchase') {
      statusFilter.value = '';
    }
    if (mode === 'themes' || mode === 'latest' || mode === 'purchase') {
      document.querySelector('#theme-filter').value = '';
    }
    for (const [buttonId, buttonMode] of [
      ['view-themes', 'themes'],
      ['view-books', 'books'],
      ['view-latest', 'latest'],
      ['view-purchase', 'purchase'],
    ]) {
      const selected = mode === buttonMode;
      const button = document.querySelector(`#${buttonId}`);
      button.classList.toggle('is-active', selected);
      button.setAttribute('aria-pressed', String(selected));
    }
  }

  function showBook(book) {
    if (!book) return;
    activeBookId = book.id;
    details.hidden = false;
    editBookForm.hidden = true;
    details.innerHTML = `
      ${book.displayCover ? `<img class="detail-cover" src="${escapeHtml(book.displayCover)}" alt="Copertina di ${escapeHtml(book.title)}">` : ''}
      <div class="detail-content">
        <span class="eyebrow book-note-color" style="--book-color:${bookColor(book.color)}">${escapeHtml(book.theme || 'LIBRO')}</span>
        <h2>${escapeHtml(book.title)}</h2>
        <p>${escapeHtml(book.author)}</p>
        <p class="pill">${escapeHtml(formatStatus(book.status))}</p>
        <p>${[book.year, book.pages ? `${book.pages} pagine` : null, book.isbn].filter(Boolean).map(escapeHtml).join(' · ')}</p>
        ${book.location ? `<div class="detail-label">Posizione</div><p>${escapeHtml(book.location)}</p>` : ''}
        ${book.plot ? `<div class="detail-label">Trama</div><p>${escapeHtml(book.plot)}</p>` : ''}
        ${book.notes ? `<div class="detail-label">Note personali</div><p>${escapeHtml(book.notes)}</p>` : ''}
        ${demoMode ? '' : '<div class="form-actions"><button id="edit-book" class="button button-primary" type="button">Modifica scheda</button><button id="delete-book-detail" class="button button-danger" type="button">Elimina libro</button></div>'}
      </div>`;
    editBookMessage.textContent = '';
    if (!demoMode) {
      document.querySelector('#edit-book').addEventListener('click', () => {
        fillEditBookForm(book);
        details.hidden = true;
        editBookForm.hidden = false;
        document.querySelector('#edit-book-title').focus();
      });
      document.querySelector('#delete-book-detail').addEventListener('click', deleteBook);
    }
    dialog.showModal();
  }

  function fillEditBookForm(book) {
    for (const field of ['title', 'author', 'theme', 'status', 'location', 'isbn', 'plot', 'notes']) {
      editBookForm.elements.namedItem(field).value = book[field] ?? '';
    }
    for (const field of ['year', 'pages']) {
      editBookForm.elements.namedItem(field).value = book[field] ?? '';
    }
    editBookForm.elements.namedItem('color').value = bookColor(book.color);
    editBookForm.elements.namedItem('cover_url').value = book.cover_url || '';
  }

  async function editBook(event) {
    event.preventDefault();
    const user = currentUser;
    const book = books.find((item) => item.id === activeBookId);
    if (demoMode || !user || !book) {
      editBookMessage.textContent = 'Accedi al tuo account per modificare la libreria.';
      return;
    }
    if (!editBookForm.reportValidity()) return;

    const formData = new FormData(editBookForm);
    const title = String(formData.get('title') || '').trim();
    const author = String(formData.get('author') || '').trim();
    const theme = String(formData.get('theme') || '').trim();
    if (!title || !author || !theme) {
      editBookMessage.textContent = 'Titolo, autore e tematica sono obbligatori.';
      return;
    }

    const saveButton = document.querySelector('#save-edit-book');
    saveButton.disabled = true;
    editBookMessage.textContent = '';
    const coverUrlValue = String(formData.get('cover_url') || '').trim() || null;
    const update = {
      title,
      author,
      theme,
      year: formData.get('year') ? Number(formData.get('year')) : null,
      pages: formData.get('pages') ? Number(formData.get('pages')) : null,
      status: String(formData.get('status') || 'to_read'),
      color: bookColor(formData.get('color')),
      location: String(formData.get('location') || '').trim() || null,
      isbn: String(formData.get('isbn') || '').trim() || null,
      cover_url: coverUrlValue,
      plot: String(formData.get('plot') || '').trim() || null,
      notes: String(formData.get('notes') || '').trim() || null,
      updated_at: new Date().toISOString(),
    };
    if (coverUrlValue !== (book.cover_url || null)) update.cover_path = null;

    try {
      const { data, error } = await client.from('books')
        .update(update)
        .eq('user_id', user.id)
        .eq('id', book.id)
        .is('deleted_at', null)
        .select('*')
        .single();
      if (error) throw error;
      const updatedBook = { ...data, displayCover: await coverUrl(data) };
      books = books.map((item) => item.id === updatedBook.id ? updatedBook : item);
      renderThemeOptions();
      renderStats();
      renderLatestNotice();
      renderBooks();
      showBook(updatedBook);
      statusMessage.textContent = 'Modifiche salvate.';
    } catch (error) {
      editBookMessage.textContent = errorMessage(error, 'Impossibile salvare le modifiche.');
    } finally {
      saveButton.disabled = false;
    }
  }

  function setLibrarySection(section) {
    const showBooks = section === 'books';
    document.querySelector('#library-books').hidden = !showBooks;
    document.querySelector('#library-settings').hidden = showBooks;
    const button = document.querySelector('#settings-toggle');
    button.textContent = showBooks ? 'Impostazioni' : 'Libri';
    button.setAttribute('aria-pressed', String(!showBooks));
  }

  function backupBookList(decoded) {
    if (Array.isArray(decoded)) return decoded;
    if (decoded && typeof decoded === 'object') {
      if (Array.isArray(decoded.books)) return decoded.books;
      if (Array.isArray(decoded.data)) return decoded.data;
    }
    return null;
  }

  function normalizeArchivePath(value) {
    const path = String(value || '').split('?')[0].replace(/\\/g, '/');
    let decoded = path;
    try {
      decoded = decodeURIComponent(path);
    } catch {
      // Keep the original path when a backup contains malformed URL escapes.
    }
    return decoded.replace(/^\/+/, '').toLocaleLowerCase('en');
  }

  function findArchiveCover(zip, reference) {
    const normalized = normalizeArchivePath(reference);
    if (!normalized) return null;
    const entries = Object.values(zip.files).filter((entry) => !entry.dir);
    return entries.find((entry) => normalizeArchivePath(entry.name) === normalized) ||
      entries.find((entry) => normalizeArchivePath(entry.name).endsWith(`/${normalized}`)) ||
      entries.find((entry) =>
        normalizeArchivePath(entry.name).split('/').pop() === normalized.split('/').pop(),
      ) || null;
  }

  function decodeCoverData(value) {
    const encoded = String(value || '');
    const dataUrl = encoded.match(/^data:(image\/[a-z0-9.+-]+);base64,(.*)$/is);
    const base64 = dataUrl ? dataUrl[2] : encoded.includes(',')
      ? encoded.slice(encoded.indexOf(',') + 1)
      : encoded;
    const binary = atob(base64);
    if (binary.length > 20 * 1024 * 1024) {
      throw new Error('Una copertina supera il limite di 20 MB.');
    }
    return {
      bytes: Uint8Array.from(binary, (character) => character.charCodeAt(0)),
      contentType: dataUrl?.[1] || 'image/jpeg',
      filename: 'copertina.jpg',
    };
  }

  async function resolveBackupCover(data, zip) {
    const base64Cover = data.cover_data ?? data.cover_base64 ?? data.image_base64;
    if (typeof base64Cover === 'string' && base64Cover.trim()) {
      return decodeCoverData(base64Cover.trim());
    }
    const reference = [
      data.cover_file, data.cover_filename, data.cover_url, data.coverUrl,
      data.cover_path, data.cover, data.image, data.image_url, data.imageUrl,
      data.image_path, data.image_filename, data.thumbnail_url, data.thumbnail,
    ].find((value) => typeof value === 'string' && value.trim());
    if (!reference) return null;
    if (/^https?:\/\//i.test(reference)) return { url: reference };
    const entry = findArchiveCover(zip, reference);
    if (!entry) return null;
    if (entry._data?.uncompressedSize > 20 * 1024 * 1024) {
      throw new Error('Una copertina supera il limite di 20 MB.');
    }
    const bytes = await entry.async('uint8array');
    if (bytes.length > 20 * 1024 * 1024) {
      throw new Error('Una copertina supera il limite di 20 MB.');
    }
    const extension = entry.name.split('.').pop()?.toLowerCase() || 'jpg';
    const contentTypes = {
      jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png',
      webp: 'image/webp', gif: 'image/gif', avif: 'image/avif',
    };
    return {
      bytes,
      contentType: contentTypes[extension] || 'application/octet-stream',
      filename: entry.name.split('/').pop() || 'copertina.jpg',
    };
  }

  async function readBackupFile(file) {
    if (file.size > 512 * 1024 * 1024) {
      throw new Error('Il backup supera il limite di 512 MB.');
    }
    if (/\.zip$/i.test(file.name)) {
      const zip = await window.JSZip.loadAsync(file);
      const entries = Object.values(zip.files).filter((entry) => !entry.dir);
      const expandedSize = entries.reduce(
        (total, entry) => total + (entry._data?.uncompressedSize || 0), 0,
      );
      if (expandedSize > 512 * 1024 * 1024) {
        throw new Error('Il contenuto del backup ZIP supera il limite di 512 MB.');
      }
      for (const entry of entries) {
        if (!entry.name.toLowerCase().endsWith('.json') ||
            entry._data?.uncompressedSize > 128 * 1024 * 1024) continue;
        try {
          const decoded = JSON.parse(await entry.async('text'));
          if (backupBookList(decoded)) return { decoded, zip };
        } catch (error) {
          if (error instanceof SyntaxError) continue;
          throw error;
        }
      }
      throw new Error('Nel file ZIP non è stato trovato un backup JSON con i libri.');
    }
    if (file.size > 128 * 1024 * 1024) {
      throw new Error('Il file JSON supera il limite di 128 MB.');
    }
    const decoded = JSON.parse(await file.text());
    if (!backupBookList(decoded)) {
      throw new Error('Il backup non contiene una lista di libri.');
    }
    return { decoded, zip: null };
  }

  function sameBookForImport(existing, incoming) {
    if (String(existing.title || '').trim().toLocaleLowerCase('it') !==
        incoming.title.toLocaleLowerCase('it') ||
        String(existing.author || '').trim().toLocaleLowerCase('it') !==
        incoming.author.toLocaleLowerCase('it')) return false;
    const oldIsbn = String(existing.isbn || '').replace(/[^0-9x]/gi, '').toLowerCase();
    const newIsbn = String(incoming.isbn || '').replace(/[^0-9x]/gi, '').toLowerCase();
    if (oldIsbn && newIsbn && oldIsbn !== newIsbn) return false;
    if (existing.year && incoming.year && Number(existing.year) !== incoming.year) return false;
    if (existing.pages && incoming.pages && Number(existing.pages) !== incoming.pages) return false;
    return true;
  }

  async function uploadBackupCover(cover, userId) {
    if (!cover) return { cover_url: null, cover_path: null };
    if (cover.url) return { cover_url: cover.url, cover_path: null };
    const safeName = cover.filename.replace(/[^a-zA-Z0-9._-]/g, '_').slice(-100);
    const path = `${userId}/${crypto.randomUUID()}-${safeName || 'cover.jpg'}`;
    const { error } = await client.storage.from('book-covers').upload(path, cover.bytes, {
      contentType: cover.contentType,
      upsert: false,
    });
    if (error) throw error;
    return { cover_url: null, cover_path: path };
  }

  async function importBackup(event) {
    event.preventDefault();
    const user = currentUser;
    const file = document.querySelector('#backup-file').files?.[0];
    if (demoMode || !user) {
      backupMessage.textContent = 'Accedi al tuo account per importare un backup.';
      return;
    }
    if (!file) {
      backupMessage.textContent = 'Seleziona un file JSON o ZIP.';
      return;
    }

    const importButton = document.querySelector('#import-backup');
    importButton.disabled = true;
    backupMessage.textContent = 'Lettura e importazione del backup…';
    try {
      const { decoded, zip } = await readBackupFile(file);
      const rawBooks = backupBookList(decoded);
      const prepared = [];
      for (const raw of rawBooks) {
        if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
          throw new Error('Un elemento del backup non è valido.');
        }
        const title = String(raw.title || '').trim();
        const author = String(raw.author || '').trim();
        if (!title || !author) {
          throw new Error('Ogni libro deve avere titolo e autore.');
        }
        const status = ['to_buy', 'to_read', 'reading', 'read'].includes(raw.status)
          ? raw.status
          : 'to_read';
        const year = raw.year === null || raw.year === '' || raw.year === undefined
          ? null : Number(raw.year);
        const pages = raw.pages === null || raw.pages === '' || raw.pages === undefined
          ? null : Number(raw.pages);
        if ((year !== null && (!Number.isInteger(year) || year < 0 || year > 9999)) ||
            (pages !== null && (!Number.isInteger(pages) || pages < 1 || pages > 100000))) {
          throw new Error(`Anno o numero di pagine non valido per "${title}".`);
        }
        prepared.push({
          title,
          author,
          theme: String(raw.theme || '').trim(),
          year,
          pages,
          status,
          color: bookColor(raw.color),
          location: String(raw.location || '').trim() || null,
          isbn: String(raw.isbn || '').trim() || null,
          plot: String(raw.plot || '').trim() || null,
          notes: String(raw.notes || '').trim() || null,
          created_at: raw.created_at && Number.isFinite(Date.parse(raw.created_at))
            ? new Date(raw.created_at).toISOString()
            : new Date().toISOString(),
          cover: await resolveBackupCover(raw, zip),
        });
      }

      const toInsert = [];
      const toUpdateCovers = [];
      const knownBooks = [...books];
      let duplicates = 0;
      for (const incoming of prepared) {
        const existing = knownBooks.find((book) => sameBookForImport(book, incoming));
        if (!existing) {
          const { cover: incomingCover, ...bookData } = incoming;
          const cover = await uploadBackupCover(incomingCover, user.id);
          const record = {
            ...bookData,
            ...cover,
            id: crypto.randomUUID(),
            user_id: user.id,
            updated_at: new Date().toISOString(),
            deleted_at: null,
          };
          toInsert.push(record);
          knownBooks.push(record);
          continue;
        }
        duplicates++;
        if (!existing.cover_url && !existing.cover_path && incoming.cover) {
          const cover = await uploadBackupCover(incoming.cover, user.id);
          toUpdateCovers.push({ id: existing.id, ...cover });
        }
      }

      if (toUpdateCovers.length) {
        for (const coverUpdate of toUpdateCovers) {
          const { id, ...cover } = coverUpdate;
          const { error } = await client.from('books').update(cover)
            .eq('user_id', user.id).eq('id', id).is('deleted_at', null);
          if (error) throw error;
        }
      }
      if (toInsert.length) {
        const { error } = await client.from('books').insert(toInsert);
        if (error) throw error;
      }
      backupForm.reset();
      backupMessage.textContent =
        `Importazione completata: ${toInsert.length} ${toInsert.length === 1 ? 'libro aggiunto' : 'libri aggiunti'}, ${duplicates} ${duplicates === 1 ? 'duplicato ignorato' : 'duplicati ignorati'}.`;
      if (toInsert.length || toUpdateCovers.length) {
        try {
          await loadBooks();
        } catch (error) {
          statusMessage.textContent = `Backup importato, ma aggiornamento della vista non riuscito: ${errorMessage(error, 'riprova con Aggiorna.')}`;
        }
      }
    } catch (error) {
      backupMessage.textContent = errorMessage(error, 'Impossibile importare il backup.');
    } finally {
      importButton.disabled = false;
    }
  }

  async function deleteBook(event) {
    const user = currentUser;
    const book = books.find((item) => item.id === activeBookId);
    if (demoMode || !user || !book) {
      editBookMessage.textContent = 'Accedi al tuo account per eliminare libri.';
      return;
    }
    if (!window.confirm(`Vuoi eliminare "${book.title}" dalla tua libreria?`)) return;

    const deleteButton = event.currentTarget;
    deleteButton.disabled = true;
    editBookMessage.textContent = '';
    try {
      const { error } = await client.from('books')
        .update({ deleted_at: new Date().toISOString() })
        .eq('user_id', user.id)
        .eq('id', book.id)
        .is('deleted_at', null)
        .select('id')
        .single();
      if (error) throw error;
      books = books.filter((item) => item.id !== book.id);
      dialog.close();
      renderThemeOptions();
      renderStats();
      renderLatestNotice();
      renderBooks();
      statusMessage.textContent = 'Libro eliminato dalla libreria.';
    } catch (error) {
      editBookMessage.textContent = errorMessage(error, 'Impossibile eliminare il libro.');
    } finally {
      deleteButton.disabled = false;
    }
  }

  async function signIn(event) {
    event.preventDefault();
    if (!client) {
      loginMessage.textContent = 'Accesso online non configurato. Puoi provare la modalità demo oppure configurare Supabase.';
      return;
    }
    const button = document.querySelector('#login-submit');
    button.disabled = true;
    loginMessage.textContent = '';
    const email = document.querySelector('#email').value.trim();
    const password = document.querySelector('#password').value;
    try {
      const { error } = await client.auth.signInWithPassword({ email, password });
      if (error) throw error;
      await loadBooks();
    } catch (error) {
      loginMessage.textContent = errorMessage(error, 'Accesso non riuscito.');
    } finally {
      button.disabled = false;
    }
  }

  async function signUp() {
    if (!client) {
      loginMessage.textContent = 'Creazione account non disponibile nella demo. Configura Supabase per attivare gli account.';
      return;
    }
    const email = document.querySelector('#email').value.trim();
    const password = document.querySelector('#password').value;
    if (!email || password.length < 6) {
      loginMessage.textContent = 'Inserisci email e password di almeno 6 caratteri.';
      return;
    }
    loginMessage.textContent = '';
    try {
      const { data, error } = await client.auth.signUp({ email, password });
      if (error) throw error;
      loginMessage.textContent = data.session
        ? 'Account creato. Ora puoi consultare la libreria.'
        : 'Account creato: controlla la posta per confermare l’email e poi accedi.';
    } catch (error) {
      loginMessage.textContent = error.message || 'Creazione account non riuscita.';
    }
  }

  if (!cloudConfigured) {
    setupWarning.hidden = false;
    showScreen(null);
  } else {
    client = window.supabase.createClient(config.url, config.anonKey);
  }

  document.querySelector('#login-form').addEventListener('submit', signIn);
  document.querySelector('#signup').addEventListener('click', signUp);
  document.querySelector('#demo-login').addEventListener('click', enterDemo);
  document.querySelector('#sign-out').addEventListener('click', async () => {
    if (demoMode) {
      demoMode = false;
      books = [];
      showScreen(null);
      document.querySelector('#library-tagline').textContent =
        'Tutti i tuoi libri, sincronizzati in un unico posto.';
      setupWarning.hidden = cloudConfigured;
      return;
    }
    if (client) {
      const { error } = await client.auth.signOut();
      if (error) {
        statusMessage.textContent = error.message;
        return;
      }
      books = [];
      showScreen(null);
    }
  });
  document.querySelector('#refresh').addEventListener('click', async () => {
    try {
      await loadBooks();
    } catch (error) {
      statusMessage.textContent = errorMessage(error, 'Aggiornamento non riuscito.');
    }
  });
  document.querySelector('#search').addEventListener('input', renderBooks);
  document.querySelector('#status-filter').addEventListener('change', renderBooks);
  document.querySelector('#theme-filter').addEventListener('change', () => {
    if (document.querySelector('#theme-filter').value &&
        libraryViewMode !== 'purchase') {
      setLibraryViewMode('books');
    }
    renderBooks();
  });
  document.querySelector('#view-themes').addEventListener('click', () => {
    setLibraryViewMode('themes');
    renderBooks();
  });
  document.querySelector('#view-books').addEventListener('click', () => {
    setLibraryViewMode('books');
    renderBooks();
  });
  document.querySelector('#view-latest').addEventListener('click', () => {
    setLibraryViewMode('latest');
    renderBooks();
  });
  document.querySelector('#view-purchase').addEventListener('click', () => {
    setLibraryViewMode('purchase');
    renderBooks();
  });
  document.querySelector('#settings-toggle').addEventListener('click', () => {
    setLibrarySection(document.querySelector('#library-settings').hidden ? 'settings' : 'books');
  });
  document.querySelector('#add-book').addEventListener('click', () => {
    if (demoMode) {
      statusMessage.textContent = 'La demo è di sola consultazione. Accedi per aggiungere libri.';
      return;
    }
    resetCatalogSearch();
    addBookMessage.textContent = '';
    document.querySelector('#book-status').value =
      libraryViewMode === 'purchase' ? 'to_buy' : 'to_read';
    addBookDialog.showModal();
    document.querySelector('#book-title').focus();
  });
  addBookForm.addEventListener('submit', addBook);
  catalogSearchButton.addEventListener('click', searchBookCatalogs);
  catalogQuery.addEventListener('input', () =>
    renderCatalogSourceLinks(catalogQuery.value.trim()),
  );
  catalogQuery.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      searchBookCatalogs();
    }
  });
  document.querySelector('#close-add-dialog').addEventListener('click', () => addBookDialog.close());
  document.querySelector('#cancel-add-book').addEventListener('click', () => addBookDialog.close());
  addBookDialog.addEventListener('click', (event) => {
    if (event.target === addBookDialog) addBookDialog.close();
  });
  document.querySelector('#close-theme-color-dialog').addEventListener('click', () => {
    themeColorDialog.close();
  });
  document.querySelector('#cancel-theme-color').addEventListener('click', () => {
    themeColorDialog.close();
  });
  document.querySelector('#save-theme-color').addEventListener('click', () => {
    if (!activeThemeForColor) return;
    try {
      saveThemeColorOverride(activeThemeForColor, themeColorInput.value);
      themeColorDialog.close();
      renderBooks();
    } catch (error) {
      themeColorMessage.textContent = error.message || String(error);
    }
  });
  document.querySelector('#reset-theme-color').addEventListener('click', () => {
    if (!activeThemeForColor) return;
    try {
      saveThemeColorOverride(activeThemeForColor, null);
      themeColorDialog.close();
      renderBooks();
    } catch (error) {
      themeColorMessage.textContent = error.message || String(error);
    }
  });
  themeColorDialog.addEventListener('click', (event) => {
    if (event.target === themeColorDialog) themeColorDialog.close();
  });
  themeColorDialog.addEventListener('close', () => {
    activeThemeForColor = null;
  });
  document.querySelector('#close-dialog').addEventListener('click', () => dialog.close());
  document.querySelector('#cancel-edit-book').addEventListener('click', () => {
    const book = books.find((item) => item.id === activeBookId);
    if (book) showBook(book);
  });
  document.querySelector('#delete-book').addEventListener('click', deleteBook);
  editBookForm.addEventListener('submit', editBook);
  editBookForm.addEventListener('input', () => {
    editBookMessage.textContent = '';
  });
  backupForm.addEventListener('submit', importBackup);
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) dialog.close();
  });

  if (client) {
    client.auth.getSession().then(async ({ data, error }) => {
      if (error) {
        loginMessage.textContent = error.message;
        return;
      }
      showScreen(data.session?.user);
      if (data.session) {
        try {
          await loadBooks();
        } catch (loadError) {
          statusMessage.textContent = errorMessage(loadError, 'Libreria non disponibile.');
        }
      }
    });
    client.auth.onAuthStateChange((_event, session) => {
      if (!demoMode) showScreen(session?.user);
    });
  }
})();
