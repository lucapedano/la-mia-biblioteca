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
  const details = document.querySelector('#book-details');
  const addBookDialog = document.querySelector('#add-book-dialog');
  const addBookForm = document.querySelector('#add-book-form');
  const addBookMessage = document.querySelector('#add-book-message');
  const demoBanner = document.querySelector('#demo-banner');
  const statusLabels = { to_read: 'Da leggere', reading: 'In corso', read: 'Letto' };
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
  ];
  let client;
  let books = [];
  let demoMode = false;
  const cloudConfigured = Boolean(
    config.url && config.anonKey &&
    !config.url.includes('YOUR_PROJECT') &&
    !config.anonKey.includes('YOUR_'),
  );

  const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
  const formatStatus = (value) => statusLabels[value] || value || 'Da leggere';

  async function coverUrl(book) {
    if (book.cover_url?.startsWith('http')) return book.cover_url;
    if (!book.cover_path) return '';
    const { data, error } = await client.storage.from('book-covers')
      .createSignedUrl(book.cover_path, 3600);
    if (error) throw error;
    return data.signedUrl;
  }

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

  function showScreen(user) {
    const signedIn = Boolean(user);
    loginView.hidden = signedIn;
    libraryView.hidden = !signedIn;
    account.hidden = !signedIn;
    demoBanner.hidden = !demoMode;
    if (user) document.querySelector('#account-email').textContent = user.email || '';
  }

  async function addBook(event) {
    event.preventDefault();
    if (demoMode || !client?.auth.currentUser) {
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

    const saveButton = document.querySelector('#save-book');
    saveButton.disabled = true;
    addBookMessage.textContent = '';
    const now = new Date().toISOString();
    const book = {
      id: crypto.randomUUID(),
      user_id: client.auth.currentUser.id,
      title,
      author,
      theme,
      year: formData.get('year') ? Number(formData.get('year')) : null,
      pages: formData.get('pages') ? Number(formData.get('pages')) : null,
      status: String(formData.get('status') || 'to_read'),
      color: '#8D6E63',
      location: String(formData.get('location') || '').trim() || null,
      isbn: String(formData.get('isbn') || '').trim() || null,
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
      addBookMessage.textContent = error.message || 'Impossibile salvare il libro.';
    } finally {
      saveButton.disabled = false;
    }
  }

  function enterDemo() {
    demoMode = true;
    books = demoBooks.map((book) => ({ ...book, displayCover: '' }));
    setupWarning.hidden = true;
    renderThemeOptions();
    document.querySelector('#library-tagline').textContent =
      'Esplora una libreria di esempio: ricerca, filtri e schede libro sono interattivi.';
    showScreen({ email: 'Demo locale' });
    renderStats();
    renderBooks();
    statusMessage.textContent = '6 libri di esempio · prova ricerca, filtri e dettagli.';
  }

  async function loadBooks() {
    statusMessage.textContent = 'Caricamento della libreria…';
    const { data, error } = await client.from('books')
      .select('*')
      .is('deleted_at', null)
      .order('title', { ascending: true });
    if (error) throw error;
    books = await Promise.all((data || []).map(async (book) => ({
      ...book,
      displayCover: await coverUrl(book),
    })));
    renderThemeOptions();
    renderStats();
    renderBooks();
    statusMessage.textContent = books.length
      ? `${books.length} ${books.length === 1 ? 'libro nella libreria' : 'libri nella libreria'}`
      : 'La libreria è vuota. Importa un backup dall’app dopo aver effettuato l’accesso.';
  }

  function renderStats() {
    const stats = [
      ['Totale libri', books.length],
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
    const status = document.querySelector('#status-filter').value;
    const theme = document.querySelector('#theme-filter').value;
    const visible = books.filter((book) => {
      const matchesText = ['title', 'author', 'theme', 'plot', 'notes', 'isbn']
        .some((field) => String(book[field] || '').toLocaleLowerCase('it').includes(query));
      return matchesText &&
        (!status || book.status === status) &&
        (!theme || String(book.theme || '').trim() === theme);
    });
    if (!visible.length) {
      grid.innerHTML = '<div class="empty">Nessun libro trovato con questi filtri.</div>';
      return;
    }
    grid.innerHTML = visible.map((book) => `
      <article class="book-card" data-id="${escapeHtml(book.id)}" tabindex="0" role="button">
        <div class="cover" style="--cover:${escapeHtml(book.color || '#8D6E63')}">
          ${book.displayCover
            ? `<img src="${escapeHtml(book.displayCover)}" alt="Copertina di ${escapeHtml(book.title)}">`
            : '<span class="cover-symbol" aria-hidden="true">▤</span>'}
        </div>
        <div class="book-info">
          <h2 class="book-title" title="${escapeHtml(book.title)}">${escapeHtml(book.title)}</h2>
          <p class="book-author">${escapeHtml(book.author)}</p>
          <div class="book-meta"><span>${escapeHtml(book.theme || 'Senza categoria')}</span><span class="pill">${escapeHtml(formatStatus(book.status))}</span></div>
        </div>
      </article>`,
    ).join('');
    grid.querySelectorAll('.book-card').forEach((card) => {
      const open = () => showBook(books.find((book) => book.id === card.dataset.id));
      card.addEventListener('click', open);
      card.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          open();
        }
      });
    });
  }

  function showBook(book) {
    if (!book) return;
    details.innerHTML = `
      ${book.displayCover ? `<img class="detail-cover" src="${escapeHtml(book.displayCover)}" alt="Copertina di ${escapeHtml(book.title)}">` : ''}
      <div class="detail-content">
        <span class="eyebrow">${escapeHtml(book.theme || 'LIBRO')}</span>
        <h2>${escapeHtml(book.title)}</h2>
        <p>${escapeHtml(book.author)}</p>
        <p class="pill">${escapeHtml(formatStatus(book.status))}</p>
        <p>${[book.year, book.pages ? `${book.pages} pagine` : null, book.isbn].filter(Boolean).map(escapeHtml).join(' · ')}</p>
        ${book.location ? `<div class="detail-label">Posizione</div><p>${escapeHtml(book.location)}</p>` : ''}
        ${book.plot ? `<div class="detail-label">Trama</div><p>${escapeHtml(book.plot)}</p>` : ''}
        ${book.notes ? `<div class="detail-label">Note personali</div><p>${escapeHtml(book.notes)}</p>` : ''}
      </div>`;
    dialog.showModal();
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
      loginMessage.textContent = error.message || 'Accesso non riuscito.';
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
      statusMessage.textContent = error.message || 'Aggiornamento non riuscito.';
    }
  });
  document.querySelector('#search').addEventListener('input', renderBooks);
  document.querySelector('#status-filter').addEventListener('change', renderBooks);
  document.querySelector('#theme-filter').addEventListener('change', renderBooks);
  document.querySelector('#add-book').addEventListener('click', () => {
    if (demoMode) {
      statusMessage.textContent = 'La demo è di sola consultazione. Accedi per aggiungere libri.';
      return;
    }
    addBookMessage.textContent = '';
    addBookDialog.showModal();
    document.querySelector('#book-title').focus();
  });
  addBookForm.addEventListener('submit', addBook);
  document.querySelector('#close-add-dialog').addEventListener('click', () => addBookDialog.close());
  document.querySelector('#cancel-add-book').addEventListener('click', () => addBookDialog.close());
  addBookDialog.addEventListener('click', (event) => {
    if (event.target === addBookDialog) addBookDialog.close();
  });
  document.querySelector('#close-dialog').addEventListener('click', () => dialog.close());
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
          statusMessage.textContent = loadError.message || 'Libreria non disponibile.';
        }
      }
    });
    client.auth.onAuthStateChange((_event, session) => {
      if (!demoMode) showScreen(session?.user);
    });
  }
})();
