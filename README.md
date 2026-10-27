# La mia Biblioteca — Flutter

© 2026 Luca Pedano (Luke)

App Flutter offline-first: libri, preferiti, impostazioni e immagini di
copertina vengono conservati localmente sul dispositivo. Senza configurare
Supabase l'app non richiede account o backend e non invia i dati a un server.
La sincronizzazione cloud è facoltativa e attiva solo dopo aver configurato un
progetto proprio e aver effettuato l'accesso.

## Dati e trasferimento

- I libri sono salvati in `library.json` nell'area privata dell'app; le
  copertine sono file locali nell'area privata dell'app.
- Su Android l'app aggiorna un backup automatico giornaliero all'avvio e dopo
  ogni modifica della libreria in `Download/LaMiaLibreria/`, mantenendo gli
  ultimi sette backup automatici. Il backup manuale da Impostazioni salva una
  copia separata nella stessa cartella. L'app deve essere aperta perché possa
  aggiornare il backup automatico.
- In **Impostazioni** puoi esportare un backup JSON con le copertine incluse e
  importare backup JSON o ZIP, anche archivi contenenti un file JSON dei libri
  e le relative immagini. Dopo l'importazione l'app mostra i libri aggiunti,
  i libri esistenti aggiornati con le copertine trovate e il totale aggiornato.
  I libri con lo stesso titolo e autore ma edizione o copertina diversa sono
  conservati separatamente; importare nuovamente lo stesso backup non crea
  copie identiche.
- Senza configurare Supabase ogni telefono mantiene la propria libreria e non
  c'è sincronizzazione tra dispositivi. Conserva una copia del backup; la
  disinstallazione dell'app può cancellare i dati locali.
- È disponibile anche una piattaforma web privata, sincronizzata con l'app via
  Supabase. La configurazione non è inclusa nel repository: occorre creare un
  progetto Supabase e configurare le chiavi pubbliche del progetto prima di
  avviare o pubblicare app e sito. Le chiavi `service_role` non devono mai
  essere inserite nell'app o nel sito.
- Le copertine caricate dall'app vengono conservate nel bucket privato
  `book-covers`. Tabelle e copertine sono protette da policy che consentono
  l'accesso solo all'utente autenticato proprietario dei dati.
- Questo workspace conteneva solo il client Flutter, non il backend originale
  né un'esportazione della libreria. Perciò i vecchi libri e le copertine
  ospitati sul server non sono stati trasferiti automaticamente. Per recuperarli
  serve un backup/esportazione dal servizio originale; l'importazione cerca
  negli archivi ZIP un JSON con una lista `books` o `data` e abbina le copertine
  incluse nell'archivio tramite `cover_file` o il nome file. Le copertine
  vengono aggiunte anche ai libri già presenti, invece di essere saltate come
  duplicati.
- La ricerca ISBN usa Google Books, IBS, NiceBooks, Open Library (incluse le
  schede delle opere) e Internet Archive via HTTPS per recuperare titolo,
  autore, anno, pagine, trama e, quando disponibile, copertina. NiceBooks può
  inoltre suggerire codici simili se l'ISBN inserito non supera la verifica;
  conferma sempre il codice corretto prima di usare i suggerimenti. La trama
  dipende dai dati presenti nei cataloghi e potrebbe non essere disponibile.
  Un errore nel download della copertina non blocca i dati bibliografici; per
  gli ISBN compatibili vengono provate sia la forma ISBN-10 sia ISBN-13. La
  ricerca richiede una connessione internet; la gestione della libreria resta
  offline.
- Dalla schermata del libro, "Leggi da foto" estrae il testo dalla copertina,
  dal retro o da una pagina fotografata, usando il riconoscimento testo locale
  del dispositivo. Il testo viene aggiunto al campo trama e può essere corretto
  prima di salvare.

## Requisiti e avvio

- Flutter SDK 3.19+ (Dart 3.3+)
- Android Studio o VS Code con l'estensione Flutter/Dart

```bash
cd biblio_app
flutter pub get
flutter run --flavor standard
flutter build apk --flavor standard --release
flutter build appbundle --flavor standard --release
```

## Piattaforma web e sincronizzazione

1. Crea un progetto Supabase e apri il relativo SQL Editor.
2. Esegui [supabase/schema.sql](./supabase/schema.sql) per creare la tabella
   privata dei libri, le policy di accesso e il bucket privato delle copertine.
3. Copia il Project URL e la chiave pubblica `anon`/publishable del progetto.
   Non usare mai la chiave `service_role`.
4. Nel progetto locale crea `supabase.local.json` (è escluso da Git) con
   l'URL e la chiave pubblica del progetto:

   ```bash
   {
     "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
     "SUPABASE_ANON_KEY": "YOUR_PUBLIC_ANON_KEY"
   }
   ```

   Avvia poi l'app con:

   ```bash
   flutter run --flavor cloud --dart-define-from-file=supabase.local.json
   ```

   Prima di sostituire o disinstallare una versione dell'app che contiene già
   libri, esporta un backup dal telefono. In Impostazioni, accedi o crea
   l'account privato e importa il backup JSON o ZIP: libri e copertine verranno
   sincronizzati sul cloud.
   Le nuove modifiche dell'app vengono inviate automaticamente. In caso di
   errore di rete le modifiche a un libro restano sul dispositivo: usa
   **Sincronizza adesso** quando la connessione ritorna. Per eliminare libri
   o svuotare la libreria mentre è attiva la sincronizzazione è necessaria la
   connessione. La libreria viene sincronizzata all'avvio, all'accesso e su
   richiesta con **Sincronizza adesso**; l'app non interroga il database a
   intervalli automatici.
5. Inserisci lo stesso URL e la stessa chiave pubblica in
   [web/config.js](./web/config.js), poi pubblica il contenuto della cartella
   `web/` su un hosting statico HTTPS. Apri il sito e accedi con lo stesso
   account dell'app. Dal sito puoi consultare la libreria, filtrare per tematica,
   aggiungere libri, modificare i dati dalla scheda di un libro, consultare gli
   ultimi dieci inserimenti e usare **Aggiorna** per rileggere le modifiche
   dell'app. Il sito ricarica i dati
   all'accesso e su richiesta con **Aggiorna**, evitando richieste automatiche
   ripetute da più schede aperte. Sito e app segnalano con un indicatore
   luminoso i libri aggiunti nelle ultime 24 ore.
   Nell'app la nuova voce **Ultimi** si trova nella barra di navigazione in
   basso e mostra gli ultimi dieci libri.

Ogni account vede e modifica soltanto la propria libreria. La chiave pubblica
può essere presente nel client perché l'autorizzazione è applicata dalle policy
RLS di Supabase.

Per provare l'interfaccia senza configurare Supabase, apri il sito e scegli
**Entra in modalità demo**. La demo mostra sei libri fittizi e permette di
provare ricerca, filtri e dettagli; non usa account e non salva né invia dati.

### Installare la versione Cloud sul telefono senza collegarlo al PC

Il flavor Android `cloud` usa l'URL e la chiave pubblica preconfigurati e
installa una seconda app, **La mia Biblioteca Cloud**, accanto all'app
esistente. È separata apposta: le firme degli APK di distribuzione esistenti
non corrispondono alla chiave di upload disponibile in questo progetto, quindi
Android non può aggiornarli in-place senza prima disinstallarli.

Per generare l'APK Cloud ARM64:

```bash
flutter build apk --flavor cloud --release --target-platform android-arm64
```

Per trasferire i dati senza PC, nell'app originale salva un backup manuale
nella cartella Download. Poi scarica e installa l'APK Cloud sul telefono,
accedi con lo stesso account e scegli **Impostazioni → Importa backup**,
selezionando il file in Download. L'app originale e i suoi dati rimangono
intatti. Android richiede comunque di confermare l'installazione; un'app non
può installarsi o aggiornarsi da sola senza l'autorizzazione dell'utente.

## Pubblicazione Android

- Il bundle da caricare su Google Play viene generato in
  `build/app/outputs/bundle/release/app-release.aab`; per altri store che
  richiedono un APK si può usare `flutter build apk --release`.
- Le release sono firmate con una chiave upload personale, non con la chiave
  debug. La chiave privata e `android/key.properties` sono esclusi da Git;
  conserva copie di sicurezza offline e protette di entrambi. Non condividere
  la chiave o le password. Se perdi la chiave upload, gli aggiornamenti
  potrebbero richiedere una procedura di reset in Play Console.
- Per Google Play attiva Play App Signing e carica l'AAB firmato con la chiave
  upload. Non modificare `applicationId` dopo la prima pubblicazione. Ogni
  aggiornamento deve incrementare il numero build dopo `+` in `pubspec.yaml`.
- Prima dell'invio completa in Play Console la scheda dell'app, la privacy
  policy, la sezione Data safety, la classificazione dei contenuti e i test
  richiesti per il tuo account. La build tecnica non garantisce da sola
  l'approvazione dello store.

## Funzioni

- Creazione, modifica, ricerca, ordinamento e raggruppamento dei libri
- Fotocamera/galleria per salvare le copertine e riconoscere il testo delle foto
- Scansione, ricerca online ISBN e salvataggio manuale dell'ISBN
- Preferiti autore e impostazioni di aspetto locali
- Backup JSON trasferibile con copertine incluse
- Backup automatici Android giornalieri per gli ultimi 7 giorni e backup
  manuali in `Download/LaMiaLibreria/`
- Rimozione dei doppioni mantenendo i dati più completi di libro
