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
    return strings.russian != oldWidget.strings.russian ||
        dark != oldWidget.dark;
  }
}

/// Theme and language live in the app bar so they do not cover the sheet or lists.
class AppearanceMenu extends StatelessWidget {
  const AppearanceMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppearanceScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final strings = scope.strings;
    return PopupMenuButton<String>(
      tooltip: strings.theme,
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'theme') scope.onTheme();
        if (value == 'language') scope.onLanguage();
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'theme', child: Text(strings.theme)),
        PopupMenuItem(
          value: 'language',
          child: Text(strings.russian ? 'EN' : 'RU'),
        ),
      ],
    );
  }
}
