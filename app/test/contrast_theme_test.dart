import 'package:field_bim_viewer/main.dart';
import 'package:field_bim_viewer/src/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme cycle is light, dark, then contrast', () {
    expect(nextViewerTheme(ViewerTheme.light), ViewerTheme.dark);
    expect(nextViewerTheme(ViewerTheme.dark), ViewerTheme.contrast);
    expect(nextViewerTheme(ViewerTheme.contrast), ViewerTheme.light);
  });

  testWidgets('the menu switches to a high-contrast dark theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FieldBimApp());
    await tester.pump();
    expect(_mark(tester), 'light');
    expect(_scheme(tester).brightness, Brightness.light);

    await _cycle(tester, 'Тема: светлая');
    expect(_mark(tester), 'dark');
    expect(_scheme(tester).brightness, Brightness.dark);

    await _cycle(tester, 'Тема: тёмная');
    expect(_mark(tester), 'contrast');
    final contrast = _scheme(tester);
    expect(contrast.brightness, Brightness.dark);
    expect(contrast.surface.computeLuminance(), lessThan(0.05));
    expect(contrast.onSurface.computeLuminance(), greaterThan(0.9));
    expect(contrast.primary.computeLuminance(), greaterThan(0.4));
    final iconSize = Theme.of(
      tester.element(find.byType(Scaffold)),
    ).iconButtonTheme.style?.minimumSize?.resolve(const <WidgetState>{});
    expect(iconSize, const Size(48, 48));

    await _cycle(tester, 'Тема: контраст');
    expect(_mark(tester), 'light');
    expect(_scheme(tester).brightness, Brightness.light);
  });
}

Future<void> _cycle(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Меню'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

String _mark(WidgetTester tester) {
  final mark = Theme.of(
    tester.element(find.byType(Scaffold)),
  ).extension<ViewerThemeMark>();
  return mark?.name ?? '';
}

ColorScheme _scheme(WidgetTester tester) {
  return Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
}
