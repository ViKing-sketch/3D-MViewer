import 'dart:io';

import 'package:flutter/material.dart';

import 'src/appearance.dart';
import 'src/library_page.dart';
import 'src/model_page.dart';
import 'src/package_import.dart';
import 'src/server_link.dart';
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
    this.initialConnectLink,
    this.tokenStore,
    this.russian = true,
  });

  final String? autoOpenPath;
  final String? initialLibrary;
  final String? initialConnectLink;
  final TokenStore? tokenStore;
  final bool russian;

  @override
  State<FieldBimApp> createState() => _FieldBimAppState();
}

class _FieldBimAppState extends State<FieldBimApp> {
  late bool _russian = widget.russian;
  ViewerTheme _themeMode = ViewerTheme.light;
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = S(_russian);
    final theme = _themeData(_themeMode);
    return MaterialApp(
      navigatorKey: _navigator,
      title: strings.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode == ViewerTheme.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      theme: _themeMode == ViewerTheme.contrast
          ? theme
          : _themeData(ViewerTheme.light),
      darkTheme: _themeMode == ViewerTheme.contrast
          ? theme
          : _themeData(ViewerTheme.dark),
      builder: (context, child) {
        return AppearanceScope(
          strings: strings,
          theme: _themeMode,
          onTheme: () => setState(() {
            _themeMode = nextViewerTheme(_themeMode);
          }),
          onLanguage: () => setState(() => _russian = !_russian),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: widget.autoOpenPath != null
          ? ModelPage(path: widget.autoOpenPath!, strings: strings)
          : LibraryPage(
              key: _library,
              strings: strings,
              initialDirectory: widget.initialLibrary,
              initialConnectLink: widget.initialConnectLink,
              tokenStore: widget.tokenStore,
            ),
    );
  }

  ThemeData _themeData(ViewerTheme mode) {
    final ColorScheme scheme;
    switch (mode) {
      case ViewerTheme.light:
        scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B3A82),
          brightness: Brightness.light,
        );
      case ViewerTheme.dark:
        scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B3A82),
          brightness: Brightness.dark,
        );
      case ViewerTheme.contrast:
        scheme = const ColorScheme.highContrastDark();
    }
    final large = mode == ViewerTheme.contrast;
    final control = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      extensions: [ViewerThemeMark(mode.name)],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: large ? TextButtonThemeData(style: control) : null,
      iconButtonTheme: large ? IconButtonThemeData(style: control) : null,
    );
  }
}
