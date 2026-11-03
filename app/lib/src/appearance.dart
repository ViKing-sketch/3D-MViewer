import 'package:flutter/material.dart';

import 'strings.dart';

class AppearanceScope extends InheritedWidget {
  const AppearanceScope({
    super.key,
    required this.strings,
    required this.dark,
    required this.onTheme,
    required this.onLanguage,
    required super.child,
  });

  final S strings;
  final bool dark;
  final VoidCallback onTheme;
  final VoidCallback onLanguage;

  static AppearanceScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppearanceScope>();
  }

  @override
  bool updateShouldNotify(AppearanceScope oldWidget) {
    return strings.russian != oldWidget.strings.russian || dark != oldWidget.dark;
  }
}

class AppearanceButtons extends StatelessWidget {
  const AppearanceButtons({super.key, this.tag = 'home'});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final scope = AppearanceScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: '$tag-theme',
          tooltip: scope.strings.theme,
          onPressed: scope.onTheme,
          child: Icon(scope.dark ? Icons.light_mode : Icons.dark_mode),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: '$tag-lang',
          tooltip: scope.strings.language,
          onPressed: scope.onLanguage,
          child: Text(scope.strings.russian ? 'EN' : 'RU'),
        ),
      ],
    );
  }
}
