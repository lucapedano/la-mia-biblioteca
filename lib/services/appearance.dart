import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode (Sistema/Chiaro/Scuro) + accent colour, persisted on device.
class AppearanceController extends ChangeNotifier {
  static const _kMode = 'theme_pref';
  static const _kAccent = 'accent_color';

  ThemeMode _mode = ThemeMode.system;
  Color? _accent;

  ThemeMode get mode => _mode;
  Color? get accent => _accent;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _mode = ThemeMode.values.firstWhere(
      (m) => m.name == p.getString(_kMode),
      orElse: () => ThemeMode.system,
    );
    final a = p.getInt(_kAccent);
    _accent = a == null ? null : Color(a);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString(_kMode, m.name);
  }

  /// `null` restores the default (black/white) accent.
  Future<void> setAccent(Color? c) async {
    _accent = c;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    if (c == null) {
      await p.remove(_kAccent);
    } else {
      await p.setInt(_kAccent, c.toARGB32());
    }
  }
}
