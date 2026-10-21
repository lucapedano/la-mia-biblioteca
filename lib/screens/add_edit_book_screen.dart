import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/isbn_lookup_service.dart';
import '../services/local_library_service.dart';
import '../theme.dart';
import '../utils/isbn.dart';
import '../widgets/book_cover_image.dart';
import 'scan_screen.dart';

/// Add or edit a book, including an ISBN and a locally stored cover photo.
class AddEditBookScreen extends StatefulWidget {
  final Book? existing;
  const AddEditBookScreen({super.key, this.existing});

  @override
  State<AddEditBookScreen> createState() => _AddEditBookScreenState();
}

class _AddEditBookScreenState extends State<AddEditBookScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _theme = TextEditingController();
  final _year = TextEditingController();
  final _pages = TextEditingController();
  final _location = TextEditingController();
  final _isbn = TextEditingController();
  final _plot = TextEditingController();
  final _notes = TextEditingController();

  String _status = 'to_read';
  String _color = '#8D6E63';
  String? _coverUrl;

  bool _saving = false;
  bool _coverBusy = false;
  bool _isbnBusy = false;
  bool _plotOcrBusy = false;
  String? _error;
  String? _isbnMessage;

  static const _palette = [
    '#8D6E63',
    '#EF5350',
    '#AB47BC',
    '#5C6BC0',
    '#29B6F6',
    '#26A69A',
    '#66BB6A',
    '#FFCA28',
    '#FF7043',
    '#78909C',
  ];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _title.text = b.title;
      _author.text = b.author;
      _theme.text = b.theme;
      _year.text = b.year?.toString() ?? '';
      _pages.text = b.pages?.toString() ?? '';
      _location.text = b.location ?? '';
      _isbn.text = b.isbn ?? '';
      _plot.text = b.plot ?? '';
      _notes.text = b.notes ?? '';
      _status = b.status;
      _color = b.color;
      _coverUrl = b.coverUrl;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _author,
      _theme,
      _year,
      _pages,
      _location,
      _isbn,
      _plot,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scanIsbn() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (code == null || !mounted) return;
    _isbn.text = code;
    await _lookupIsbn();
  }

  Future<void> _lookupIsbn() async {
    final enteredCode = _isbn.text.trim();
    if (enteredCode.isEmpty) {
      _toast('Inserisci o scansiona il codice ISBN del libro.');
      return;
    }
    final isbn = normalizeIsbn(enteredCode) ?? enteredCode;
    final lookup = IsbnLookupService();
    final library = context.read<LocalLibraryService>();
    setState(() {
      _isbn.text = isbn;
      _isbnBusy = true;
      _isbnMessage = null;
    });
    try {
      final details = await lookup.lookup(isbn);
      if (!mounted) return;
      setState(() {
        _title.text = details.title;
        if (details.author != null) _author.text = details.author!;
        if (details.year != null) _year.text = '${details.year}';
        if (details.pages != null) _pages.text = '${details.pages}';
        if (details.plot != null) _plot.text = details.plot!;
        if (details.theme != null && _theme.text.trim().isEmpty) {
          _theme.text = details.theme!;
        }
      });
      if (details.coverBytes != null) {
        final coverPath = await library.saveCover(
          details.coverBytes!,
          'isbn-cover${details.coverExtension ?? '.jpg'}',
        );
        if (mounted) setState(() => _coverUrl = coverPath);
      }
      if (mounted) {
        setState(() {
          _isbnMessage = details.plot == null
              ? 'Libro trovato. La trama non è disponibile nel catalogo online.'
              : 'Dati e trama caricati online.';
        });
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst(
              RegExp(r'^(?:Exception|FormatException): '),
              '',
            );
        setState(() => _isbnMessage = message);
      }
    } finally {
      lookup.close();
      if (mounted) setState(() => _isbnBusy = false);
    }
  }

  Future<List<int>?> _pickBytes() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Scatta foto'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Scegli dalla galleria'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src == null) return null;
    final x = await ImagePicker().pickImage(source: src, imageQuality: 85);
    if (x == null) return null;
    return x.readAsBytes();
  }

  Future<void> _extractPlotFromPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Scatta foto di copertina, retro o pagina'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Scegli una foto dalla galleria'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 100,
    );
    if (image == null || !mounted) return;

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    setState(() => _plotOcrBusy = true);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      final extractedText = result.text.trim();
      if (!mounted) return;
      if (extractedText.isEmpty) {
        _toast(
            'Nessun testo leggibile nella foto. Prova con più luce e a fuoco.');
        return;
      }
      setState(() {
        final currentPlot = _plot.text.trim();
        if (currentPlot.isEmpty) {
          _plot.text = extractedText;
        } else if (!currentPlot.contains(extractedText)) {
          _plot.text = '$currentPlot\n\n$extractedText';
        }
      });
      _toast(
          'Testo riconosciuto e aggiunto alla trama. Controllalo prima di salvare.');
    } catch (error) {
      if (mounted) {
        _toast('Impossibile leggere il testo dalla foto: $error');
      }
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _plotOcrBusy = false);
    }
  }

  Future<void> _uploadCover() async {
    final library = context.read<LocalLibraryService>();
    final bytes = await _pickBytes();
    if (bytes == null || !mounted) return;
    setState(() => _coverBusy = true);
    try {
      final path = await library.saveCover(bytes, 'cover.jpg');
      if (!mounted) return;
      setState(() => _coverUrl = path);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = {
      'title': _title.text.trim(),
      'author': _author.text.trim(),
      'theme': _theme.text.trim(),
      'year': int.tryParse(_year.text.trim()),
      'color': _color,
      'pages': int.tryParse(_pages.text.trim()),
      'status': _status,
      'plot': _plot.text.trim().isEmpty ? null : _plot.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
      'cover_url': _coverUrl,
      'isbn': _isbn.text.trim().isEmpty ? null : _isbn.text.trim(),
    };
    try {
      final api = context.read<LocalLibraryService>();
      if (_isEdit) {
        await api.update(widget.existing!.id, payload);
      } else {
        await api.create(payload);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Modifica libro' : 'Nuovo libro')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Barcode scan
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scansiona ISBN'),
              onPressed: _isbnBusy ? null : _scanIsbn,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _isbn,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ISBN (facoltativo)',
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                    onFieldSubmitted: (_) => _lookupIsbn(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _isbnBusy ? null : _lookupIsbn,
                    child: _isbnBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Cerca online'),
                  ),
                ),
              ],
            ),
            if (_isbnMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                _isbnMessage!,
                style: TextStyle(
                  color: _isbnMessage!.startsWith('Dati')
                      ? AppColors.muted
                      : _isbnMessage!.startsWith('Libro trovato')
                          ? AppColors.muted
                          : AppColors.error,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 16),
            _coverSection(),
            const SizedBox(height: 16),
            _req(_title, 'Titolo *'),
            const SizedBox(height: 12),
            _req(_author, 'Autore *'),
            const SizedBox(height: 12),
            _req(_theme, 'Tematica *'),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ActionChip(
                  avatar: const Icon(Icons.language, size: 18),
                  label: const Text('English books'),
                  onPressed: () {
                    setState(() => _theme.text = 'English books');
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _req(_year, 'Anno *', number: true)),
                const SizedBox(width: 12),
                Expanded(child: _opt(_pages, 'Pagine', number: true)),
              ],
            ),
            const SizedBox(height: 12),
            _opt(_location, 'Posizione scaffale'),
            const SizedBox(height: 16),
            const Text('Stato di lettura',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'to_read', label: Text('Da leggere')),
                ButtonSegment(value: 'reading', label: Text('In corso')),
                ButtonSegment(value: 'read', label: Text('Letto')),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            const SizedBox(height: 16),
            const Text('Colore', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _palette.map((hex) {
                final selected = hex.toLowerCase() == _color.toLowerCase();
                return GestureDetector(
                  onTap: () => setState(() => _color = hex),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colorFromHex(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            selected ? AppColors.onSurface : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check,
                            size: 18, color: contrastOn(colorFromHex(hex)))
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _plotSection(),
            const SizedBox(height: 12),
            _opt(_notes, 'Note', lines: 3),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Salva modifiche' : 'Aggiungi libro'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverSection() {
    return Row(
      children: [
        Container(
          width: 90,
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.surfaceTertiary,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: BookCoverImage(
            path: _coverUrl,
            placeholder:
                const Icon(Icons.image_outlined, color: AppColors.muted),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _coverBusy ? null : _uploadCover,
            icon: _coverBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.photo_camera_outlined),
            label: const Text('Copertina'),
          ),
        ),
      ],
    );
  }

  Widget _plotSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child:
                  Text('Trama', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: _plotOcrBusy ? null : _extractPlotFromPhoto,
              icon: _plotOcrBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(_plotOcrBusy ? 'Lettura...' : 'Leggi da foto'),
            ),
          ],
        ),
        const Text(
          'Fotografa il retro, la copertina o una pagina: il testo verrà aggiunto qui.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        TextFormField(
          controller: _plot,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Trama / sinossi'),
        ),
      ],
    );
  }

  Widget _req(TextEditingController c, String label, {bool number = false}) {
    return TextFormField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null,
    );
  }

  Widget _opt(TextEditingController c, String label,
      {bool number = false, int lines = 1}) {
    return TextFormField(
      controller: c,
      maxLines: lines,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
    );
  }
}
