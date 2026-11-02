import 'package:flutter/material.dart';

import 'src/library_page.dart';
import 'src/model_page.dart';
import 'src/sqlite_setup.dart';
import 'src/strings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureSqlite();
  runApp(const FieldBimApp());
}

class FieldBimApp extends StatefulWidget {
  const FieldBimApp({
    super.key,
    this.autoOpenPath,
    this.initialLibrary,
    this.russian = true,
  });

  final String? autoOpenPath;
  final String? initialLibrary;
  final bool russian;

  @override
  State<FieldBimApp> createState() => _FieldBimAppState();
}

class _FieldBimAppState extends State<FieldBimApp> {
  late bool _russian = widget.russian;
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    final strings = S(_russian);
    return MaterialApp(
      title: strings.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Scaffold(
        body: widget.autoOpenPath != null
            ? ModelPage(path: widget.autoOpenPath!, strings: strings)
            : LibraryPage(strings: strings, initialDirectory: widget.initialLibrary),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
              heroTag: 'theme',
              tooltip: strings.theme,
              onPressed: () => setState(() {
                _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
              }),
              child: Icon(_mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'lang',
              tooltip: strings.language,
              onPressed: () => setState(() => _russian = !_russian),
              child: Text(_russian ? 'EN' : 'RU'),
            ),
          ],
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0B3A82), brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }
}
