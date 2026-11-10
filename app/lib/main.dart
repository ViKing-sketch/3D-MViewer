import 'dart:io';

import 'package:flutter/material.dart';

import 'src/appearance.dart';
import 'src/library_page.dart';
import 'src/model_page.dart';
import 'src/package_import.dart';
import 'src/sqlite_setup.dart';
import 'src/strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await prepareSqlite();
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
  final _navigator = GlobalKey<NavigatorState>();
  final _library = GlobalKey<LibraryPageState>();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid && widget.autoOpenPath == null) {
      PackageImport.bind(onOpened: _openImported, onFailed: _showImportError);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final pending = await PackageImport.takePending();
        if (pending != null) _openImported(pending);
      });
    }
  }

  void _openImported(String path) {
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (context) => ModelPage(path: path, strings: S(_russian)),
          ),
        )
        .then((_) => _library.currentState?.scan());
  }

  void _showImportError(String message) {
    final context = _navigator.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = S(_russian);
    return MaterialApp(
      navigatorKey: _navigator,
      title: strings.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      builder: (context, child) {
        return AppearanceScope(
          strings: strings,
          dark: _mode == ThemeMode.dark,
          onTheme: () => setState(() {
            _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
          }),
          onLanguage: () => setState(() => _russian = !_russian),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: widget.autoOpenPath != null
          ? ModelPage(path: widget.autoOpenPath!, strings: strings)
          : LibraryPage(key: _library, strings: strings, initialDirectory: widget.initialLibrary),
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
