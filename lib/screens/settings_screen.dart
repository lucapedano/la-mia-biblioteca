import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/cloud_config.dart';
import '../services/appearance.dart';
import '../services/local_library_service.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onLibraryChanged;
  const SettingsScreen({super.key, this.onLibraryChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _accents = [
    '#00897B',
    '#E53935',
    '#FB8C00',
    '#F9A825',
    '#43A047',
    '#1E88E5',
    '#8E24AA',
    '#EC407A',
    '#6D4C41',
    '#546E7A',
  ];

  String? _busy;
  String? _automaticBackupTime;
  String? _automaticBackupError;

  @override
  void initState() {
    super.initState();
    _loadAutomaticBackupStatus();
  }

  Future<void> _loadAutomaticBackupStatus() async {
    try {
      final status =
          await context.read<LocalLibraryService>().automaticBackupStatus();
      if (!mounted) return;
      setState(() {
        _automaticBackupTime = status['last'];
        _automaticBackupError = status['error'];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _automaticBackupError = '$error');
    }
  }

  String _formatBackupTime(String? iso) {
    final date = DateTime.tryParse(iso ?? '');
    if (date == null) return 'Non ancora creato';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} ${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(String action, Future<void> Function() callback) async {
    if (_busy != null) return;
    setState(() => _busy = action);
    try {
      await callback();
    } catch (error) {
      _toast('$error');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _exportManualBackup() => _run('manual-backup', () async {
        final name =
            await context.read<LocalLibraryService>().createManualBackup();
        _toast('Backup salvato in Download/LaMiaLibreria/$name');
      });

  Future<void> _import() => _run('import', () async {
        final library = context.read<LocalLibraryService>();
        final selection = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json', 'zip'],
          withData: false,
        );
        final file = selection?.files.single;
        if (file == null) return;
        final path = file.path;
        if (path == null) {
          throw const FormatException(
            'Impossibile accedere al file selezionato. Copialo sul dispositivo e riprova.',
          );
        }
        final result = await library.importLibraryFile(File(path));
        _toast(
          '${result.imported} libri aggiunti · ${result.updated} libri '
          'aggiornati · ${result.covers} copertine copiate · '
          '${result.total} libri in totale',
        );
        if (result.imported > 0 || result.updated > 0) {
          widget.onLibraryChanged?.call();
        }
      });

  Future<void> _dedupe() => _run('dedupe', () async {
        final count =
            await context.read<LocalLibraryService>().removeDuplicates();
        _toast(
            count == 0 ? 'Nessun doppione trovato' : '$count doppioni rimossi');
      });

  Future<void> _connectCloud() async {
    final client = configuredSupabaseClient;
    if (client == null) return;
    final library = context.read<LocalLibraryService>();
    final credentials = await showDialog<_CloudCredentials>(
      context: context,
      builder: (_) => const _CloudLoginDialog(),
    );
    if (credentials == null || !mounted) return;
    await _run('cloud', () async {
      if (credentials.createAccount) {
        await client.auth.signUp(
          email: credentials.email,
          password: credentials.password,
        );
        if (client.auth.currentUser == null) {
          _toast(
              'Controlla la tua email per confermare l’account, poi accedi.');
          return;
        }
      } else {
        await client.auth.signInWithPassword(
          email: credentials.email,
          password: credentials.password,
        );
      }
      await library.syncWithCloud();
      _toast('Libreria sincronizzata con il cloud.');
      widget.onLibraryChanged?.call();
    });
  }

  Future<void> _syncCloud() {
    final library = context.read<LocalLibraryService>();
    return _run('cloud', () async {
      await library.syncWithCloud();
      _toast('Libreria sincronizzata con il cloud.');
      widget.onLibraryChanged?.call();
    });
  }

  Future<void> _disconnectCloud() => _run('cloud', () async {
        await configuredSupabaseClient?.auth.signOut();
        _toast('Disconnesso dal cloud. I dati locali restano sul dispositivo.');
      });

  Future<void> _clear() async {
    if (!await _confirm(
      'Svuota libreria',
      'Verranno eliminati tutti i libri e le copertine da questo dispositivo. '
          'Esporta prima un backup se vuoi conservarli.',
      'Svuota',
    )) {
      return;
    }
    await _run('clear', () async {
      final count = await context.read<LocalLibraryService>().clearLibrary();
      _toast('Libreria svuotata ($count libri rimossi)');
    });
  }

  @override
  Widget build(BuildContext context) {
    final look = context.watch<AppearanceController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Text(
            'Impostazioni',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              const _Label('ASPETTO'),
              _Section(
                children: [
                  for (final option in const [
                    (ThemeMode.system, 'Sistema', Icons.smartphone),
                    (ThemeMode.light, 'Chiaro', Icons.light_mode_outlined),
                    (ThemeMode.dark, 'Scuro', Icons.dark_mode_outlined),
                  ])
                    _Row(
                      icon: option.$3,
                      title: option.$2,
                      trailing: Icon(
                        look.mode == option.$1
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      onTap: () => look.setMode(option.$1),
                    ),
                ],
              ),
              const _Label('COLORE PRINCIPALE'),
              _Section(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _Swatch(
                          color: null,
                          selected: look.accent == null,
                          onTap: () => look.setAccent(null),
                        ),
                        for (final hex in _accents)
                          _Swatch(
                            color: colorFromHex(hex),
                            selected: look.accent?.toARGB32() ==
                                colorFromHex(hex).toARGB32(),
                            onTap: () => look.setAccent(colorFromHex(hex)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const _Label('DATI SUL DISPOSITIVO'),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  context.watch<LocalLibraryService>().isCloudConnected
                      ? 'I dati vengono conservati su questo dispositivo e '
                          'sincronizzati con il tuo account cloud quando sei online.'
                      : 'I libri restano salvati su questo dispositivo finché '
                          'non accedi a un account cloud. Puoi sempre trasferirli '
                          'con un backup.',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
              const _Label('SINCRONIZZAZIONE PRIVATA'),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  !isCloudConfigured
                      ? 'Configura Supabase per sincronizzare la libreria tra app e sito web. '
                          'Finché non è configurato, i dati restano solo sul dispositivo.'
                      : context.watch<LocalLibraryService>().isCloudConnected
                          ? 'Connesso come ${context.watch<LocalLibraryService>().cloudEmail}. '
                              'Le modifiche vengono sincronizzate e il sito web privato usa lo stesso account.'
                          : 'Accedi o crea un account per condividere la libreria tra app e sito web.',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
              if (context.watch<LocalLibraryService>().cloudSyncError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Ultimo errore di sincronizzazione: '
                    '${context.watch<LocalLibraryService>().cloudSyncError}',
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              if (isCloudConfigured)
                _Section(
                  children: [
                    if (!context.watch<LocalLibraryService>().isCloudConnected)
                      _Row(
                        icon: Icons.cloud_outlined,
                        title: 'Accedi / crea account',
                        subtitle: 'Sincronizzazione privata con Supabase',
                        busy: _busy == 'cloud',
                        onTap: _connectCloud,
                      )
                    else ...[
                      _Row(
                        icon: Icons.sync,
                        title: 'Sincronizza adesso',
                        subtitle: 'Unisce i dati del dispositivo con il cloud',
                        busy: _busy == 'cloud',
                        onTap: _syncCloud,
                      ),
                      _Row(
                        icon: Icons.cloud_off_outlined,
                        title: 'Disconnetti account',
                        busy: _busy == 'cloud',
                        onTap: _disconnectCloud,
                      ),
                    ],
                  ],
                ),
              _Section(
                children: [
                  _Row(
                    icon: Icons.autorenew,
                    title: 'Backup automatico · ultimi 7 giorni',
                    subtitle: _automaticBackupError == null
                        ? 'Si aggiorna all’apertura e dopo le modifiche · '
                            'Download/LaMiaLibreria · '
                            'ultimo: ${_formatBackupTime(_automaticBackupTime)}'
                        : 'Errore: $_automaticBackupError',
                    onTap: _loadAutomaticBackupStatus,
                  ),
                  _Row(
                    icon: Icons.save_outlined,
                    title: 'Salva backup manuale in Download',
                    subtitle:
                        'Salva libri e copertine in Download/LaMiaLibreria',
                    busy: _busy == 'manual-backup',
                    onTap: _exportManualBackup,
                  ),
                  _Row(
                    icon: Icons.restore,
                    title: 'Importa backup',
                    subtitle:
                        'Importa backup JSON o ZIP, anche dal vecchio server',
                    busy: _busy == 'import',
                    onTap: _import,
                  ),
                  _Row(
                    icon: Icons.content_copy_outlined,
                    title: 'Rimuovi doppioni',
                    busy: _busy == 'dedupe',
                    onTap: _dedupe,
                  ),
                  _Row(
                    icon: Icons.delete_outline,
                    title: 'Svuota libreria',
                    danger: true,
                    busy: _busy == 'clear',
                    onTap: _clear,
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 28),
                child: Center(
                  child: Text(
                    '© 2026 Luca Pedano (Luke)',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CloudCredentials {
  final String email;
  final String password;
  final bool createAccount;

  const _CloudCredentials(this.email, this.password, this.createAccount);
}

class _CloudLoginDialog extends StatefulWidget {
  const _CloudLoginDialog();

  @override
  State<_CloudLoginDialog> createState() => _CloudLoginDialogState();
}

class _CloudLoginDialogState extends State<_CloudLoginDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _createAccount = false;
  String? _validationError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_createAccount ? 'Crea account' : 'Accedi al cloud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            TextButton(
              onPressed: () => setState(() => _createAccount = !_createAccount),
              child: Text(
                _createAccount ? 'Ho già un account' : 'Non ho un account',
              ),
            ),
            if (_validationError != null)
              Text(
                _validationError!,
                style: const TextStyle(color: AppColors.error),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              final email = _email.text.trim();
              final password = _password.text;
              if (email.isEmpty || password.length < 6) {
                setState(() {
                  _validationError =
                      'Inserisci un’email e una password di almeno 6 caratteri.';
                });
                return;
              }
              Navigator.pop(
                context,
                _CloudCredentials(email, password, _createAccount),
              );
            },
            child: Text(_createAccount ? 'Crea account' : 'Accedi'),
          ),
        ],
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  final List<Widget> children;
  const _Section({required this.children});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) items.add(const Divider(height: 1));
      items.add(children[index]);
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: items),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool danger;
  final bool busy;
  final VoidCallback? onTap;

  const _Row({
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.danger = false,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : null;
    return ListTile(
      minVerticalPadding: 12,
      leading: icon == null ? null : Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : trailing,
      onTap: busy ? null : onTap,
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? onSurface : AppColors.border,
            width: selected ? 3 : 1,
          ),
        ),
        child: color == null
            ? Icon(Icons.palette_outlined, size: 20, color: onSurface)
            : selected
                ? Icon(Icons.check, color: contrastOn(color!))
                : null,
      ),
    );
  }
}
