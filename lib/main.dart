import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import 'services/appearance.dart';
import 'services/cloud_config.dart';
import 'services/local_library_service.dart';
import 'theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeCloud();
  final library = await LocalLibraryService.open(
    cloudClient: configuredSupabaseClient,
  );
  runApp(MyApp(library: library));
  unawaited(library.createAutomaticBackup());
}

class MyApp extends StatelessWidget {
  final LocalLibraryService library;
  const MyApp({super.key, required this.library});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<LocalLibraryService>.value(value: library),
        ChangeNotifierProvider<AppearanceController>(
            create: (_) => AppearanceController()..load()),
      ],
      child: Consumer<AppearanceController>(
        builder: (context, look, _) => MaterialApp(
          title: 'La mia Biblioteca',
          debugShowCheckedModeBanner: false,
          themeMode: look.mode,
          theme: buildTheme(look.accent, Brightness.light),
          darkTheme: buildTheme(look.accent, Brightness.dark),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
