import 'package:flutter/material.dart';

import 'strings.dart';

enum ViewerTheme { light, dark, contrast }

class ViewerThemeMark extends ThemeExtension<ViewerThemeMark> {
  const ViewerThemeMark(this.name);

  final String name;

  @override
  ViewerThemeMark copyWith({String? name}) =>
      ViewerThemeMark(name ?? this.name);

  @override
  ViewerThemeMark lerp(ThemeExtension<ViewerThemeMark>? other, double t) =>
      this;
}

ViewerTheme nextViewerTheme(ViewerTheme theme) {
  return switch (theme) {
    ViewerTheme.light => ViewerTheme.dark,
    ViewerTheme.dark => ViewerTheme.contrast,
    ViewerTheme.contrast => ViewerTheme.light,
  };
}

class AppearanceScope extends InheritedWidget {
  const AppearanceScope({
    super.key,
    required this.strings,
    required this.theme,
    required this.onTheme,
    required this.onLanguage,
    required super.child,
  });

  final S strings;
  final ViewerTheme theme;
  final VoidCallback onTheme;
  final VoidCallback onLanguage;

  static AppearanceScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppearanceScope>();
  }

  @override
  bool updateShouldNotify(AppearanceScope oldWidget) {
    return strings.russian != oldWidget.strings.russian ||
        theme != oldWidget.theme;
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
      tooltip: strings.menu,
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'theme') scope.onTheme();
        if (value == 'language') scope.onLanguage();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'theme',
          child: Text(strings.themeMode(scope.theme.name)),
        ),
        PopupMenuItem(
          value: 'language',
          child: Text(strings.russian ? 'EN' : 'RU'),
        ),
      ],
    );
  }
}
