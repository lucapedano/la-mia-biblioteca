import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/isbn.dart';

/// Full-screen ISBN barcode scanner. Pops with the scanned or typed ISBN.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _manual = TextEditingController();
  bool _done = false;
  bool _barcodeWarningShown = false;

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _finish(String code, {bool fromBarcode = false}) {
    if (_done) return;
    final isbn = normalizeIsbn(code);
    final scannedDigits =
        code.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    final canSearchNearMatch = RegExp(r'^\d{10,14}$').hasMatch(scannedDigits);
    if ((fromBarcode && scannedDigits.length != 13) ||
        (!fromBarcode && isbn == null && !canSearchNearMatch)) {
      if (!fromBarcode) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Codice "$scannedDigits" non valido (${scannedDigits.length} '
              'cifre). Inserisci un ISBN-10 o ISBN-13 con cifra di controllo corretta.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      } else if (!_barcodeWarningShown) {
        _barcodeWarningShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Il codice a barre letto non è un ISBN-13. Cerca il codice ISBN '
              'accanto al prezzo oppure inseriscilo manualmente.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    _done = true;
    Navigator.of(context).pop(isbn ?? scannedDigits);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scansiona ISBN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    for (final b in capture.barcodes) {
                      final v = b.rawValue;
                      if (v != null && v.isNotEmpty) {
                        _finish(v, fromBarcode: true);
                        if (_done) break;
                      }
                    }
                  },
                  errorBuilder: (context, error) =>
                      _PermissionError(error: error),
                ),
                IgnorePointer(
                  child: Container(
                    width: 280,
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 24,
                  child: Text(
                    'Inquadra il codice ISBN-13 sul retro del libro',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manual,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(
                        hintText: 'Oppure scrivi l\'ISBN',
                        fillColor: Colors.white,
                        filled: true,
                      ),
                      onSubmitted: _finish,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: () => _finish(_manual.text),
                      child: const Text('Cerca'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionError extends StatelessWidget {
  final MobileScannerException error;
  const _PermissionError({required this.error});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined,
              color: Colors.white, size: 48),
          const SizedBox(height: 12),
          Text(
            denied
                ? 'Serve la fotocamera per leggere il codice ISBN.\n'
                    'Abilitala nelle impostazioni del telefono, oppure scrivi l\'ISBN qui sotto.'
                : 'Fotocamera non disponibile. Scrivi l\'ISBN qui sotto.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
