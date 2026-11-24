import 'dart:convert';
import 'dart:io';

import 'package:field_bim_viewer/main.dart';
import 'package:field_bim_viewer/src/filament_channel.dart';
import 'package:field_bim_viewer/src/named_views.dart';
import 'package:field_bim_viewer/src/named_views_section.dart';
import 'package:field_bim_viewer/src/remarks.dart';
import 'package:field_bim_viewer/src/strings.dart';
import 'package:field_bim_viewer/src/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a named view stays beside the package and out of sync', () {
    final root = Directory.systemTemp.createTempSync('fbv-views-');
    final package = Directory(p.join(root.path, 'model'))..createSync();
    final manifest = File(p.join(package.path, 'manifest.json'))
      ..writeAsStringSync('{"format_version":1}');
    File(p.join(package.path, 'brep.pack')).writeAsBytesSync([1, 2, 3]);
    final clock = DateTime.utc(2026, 11, 24, 18);
    final store = NamedViewStore(
      package.path,
      now: () => clock,
      ids: RemarkIds(),
    )..load();
    expect(store.views, isEmpty);
    expect(store.loadError, isNull);

    const saved = RemarkViewpoint(
      eyeX: 1.5,
      eyeY: 2.5,
      eyeZ: 3.5,
      dirX: 0,
      dirY: 1,
      dirZ: 0,
      storeyId: 4,
      ifcClass: 'IfcWall',
      material: '',
      systemId: 2,
      section: SectionView(enabled: true, axis: 'y', offset: 0.25, flip: true),
      hidden: [3],
      isolated: [7, 8],
    );
    expect(
      () => store.add(name: '   ', viewpoint: saved, xray: false),
      throwsA(isA<NamedViewNameException>()),
    );
    expect(
      () => store.add(name: 'я' * 81, viewpoint: saved, xray: false),
      throwsA(
        isA<NamedViewNameException>().having((e) => e.empty, 'empty', isFalse),
      ),
    );
    expect(File('${package.path}.views.json').existsSync(), isFalse);

    final first = store.add(name: '  Узел  ', viewpoint: saved, xray: true);
    store.add(
      name: 'Узел',
      viewpoint: const RemarkViewpoint(
        eyeX: 0,
        eyeY: 0,
        eyeZ: 1,
        dirX: 0,
        dirY: 0,
        dirZ: 1,
      ),
      xray: false,
    );
    expect(first.name, 'Узел');
    expect(first.createdUtc, '2026-11-24T18:00:00.000Z');
    expect(File('${package.path}.views.json.fbv-tmp').existsSync(), isFalse);
    expect(manifest.readAsStringSync(), '{"format_version":1}');
    expect(File(p.join(package.path, 'brep.pack')).readAsBytesSync(), [
      1,
      2,
      3,
    ]);
    expect(File('${package.path}.remarks.json').existsSync(), isFalse);
    expect(Directory(package.path).listSync().length, 2);

    final again = NamedViewStore(package.path)..load();
    expect(again.loadError, isNull);
    expect(again.views, hasLength(2));
    final back = again.views.first;
    expect(back.id, first.id);
    expect(back.xray, isTrue);
    expect(back.viewpoint.eyeX, closeTo(1.5, 1e-9));
    expect(back.viewpoint.material, '');
    expect(back.viewpoint.systemId, 2);
    expect(back.viewpoint.storeyId, 4);
    expect(back.viewpoint.ifcClass, 'IfcWall');
    expect(back.viewpoint.hidden, [3]);
    expect(back.viewpoint.isolated, [7, 8]);
    expect(back.viewpoint.section.enabled, isTrue);
    expect(back.viewpoint.section.axis, 'y');
    expect(back.viewpoint.section.offset, closeTo(0.25, 1e-9));
    expect(back.viewpoint.section.flip, isTrue);
    final pose = back.viewpoint.filament;
    expect(pose.eye[1], closeTo(3.5, 1e-9));
    expect(pose.target[0], closeTo(pose.eye[0], 1e-9));

    again.remove('missing');
    again.remove(first.id);
    final left = NamedViewStore(package.path)..load();
    expect(left.views, hasLength(1));
    expect(left.views.single.xray, isFalse);

    final catalog = syncCatalog(root.path);
    expect(
      catalog.files.map((file) => file.path),
      isNot(contains('model.views.json')),
    );
    expect(
      catalog.files.map((file) => file.path),
      contains('model/manifest.json'),
    );
  });

  test('a bad views file does not invent a view', () {
    final root = Directory.systemTemp.createTempSync('fbv-views-bad-');
    final package = p.join(root.path, 'model');
    File('$package.views.json').writeAsStringSync('{');
    final broken = NamedViewStore(package)..load();
    expect(broken.views, isEmpty);
    expect(broken.loadError, isNotNull);

    File('$package.views.json').writeAsStringSync(
      jsonEncode({
        'kind': 'other',
        'views': [
          {
            'id': '1',
            'name': 'Чужой',
            'viewpoint': {
              'eye': [0, 0, 0],
              'direction': [0, 1, 0],
            },
          },
        ],
      }),
    );
    final foreign = NamedViewStore(package)..load();
    expect(foreign.views, isEmpty);
    expect(foreign.loadError, contains('other'));

    File('$package.views.json').writeAsStringSync(
      jsonEncode({
        'kind': 'fbv-views-1',
        'views': [
          {'id': '', 'name': 'пусто'},
          {'id': 'ok', 'name': '   '},
          {
            'id': 'keep',
            'name': ' План ',
            'xray': false,
            'viewpoint': {
              'eye': [1, 2, 3],
              'direction': [0, 1, 0],
              'hidden': [4, 'no'],
              'isolated': [5],
            },
          },
        ],
      }),
    );
    final mixed = NamedViewStore(package)..load();
    expect(mixed.loadError, isNull);
    expect(mixed.views, hasLength(1));
    expect(mixed.views.single.name, 'План');
    expect(mixed.views.single.xray, isFalse);
    expect(mixed.views.single.viewpoint.hidden, [4]);
    expect(mixed.views.single.viewpoint.isolated, [5]);
  });

  testWidgets('the section saves a name and opens that view', (tester) async {
    final root = Directory.systemTemp.createTempSync('fbv-views-ui-');
    final store = NamedViewStore(
      p.join(root.path, 'model'),
      now: () => DateTime.utc(2026, 11, 24, 19),
      ids: RemarkIds(),
    );
    NamedView? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NamedViewsSection(
            strings: const S(true),
            store: store,
            xray: true,
            capture: () async => const RemarkViewpoint(
              eyeX: 1,
              eyeY: 0,
              eyeZ: 2,
              dirX: 0,
              dirY: 1,
              dirZ: 0,
              ifcClass: 'IfcSlab',
            ),
            onOpen: (view) => opened = view,
            onChanged: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('named-view-save')));
    await tester.pump();
    expect(find.text('Введите имя вида'), findsOneWidget);
    expect(store.views, isEmpty);

    await tester.enterText(find.byKey(const Key('named-view-name')), 'Плита');
    await tester.tap(find.byKey(const Key('named-view-save')));
    await tester.pump();
    expect(find.text('Плита'), findsOneWidget);
    expect(store.views.single.xray, isTrue);
    expect(store.views.single.viewpoint.ifcClass, 'IfcSlab');

    await tester.tap(
      find.byKey(ValueKey('named-view-${store.views.single.id}')),
    );
    await tester.pump();
    expect(opened?.name, 'Плита');

    await tester.tap(
      find.byKey(ValueKey('named-view-delete-${store.views.single.id}')),
    );
    await tester.pump();
    expect(find.text('Сохранённых видов нет'), findsOneWidget);
    expect(store.views, isEmpty);
  });

  testWidgets('opening a saved view restores filters and leaves orbit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = Directory(_repoFile('testdata/sample_model'));
    final copy = Directory.systemTemp.createTempSync('fbv-views-model-');
    addTearDown(() => copy.deleteSync(recursive: true));
    _copyPackage(source, copy);
    final before = _packageListing(copy);
    final manifest = File(
      p.join(copy.path, 'manifest.json'),
    ).readAsStringSync();

    await tester.pumpWidget(FieldBimApp(autoOpenPath: copy.path));
    await tester.pump();
    await tester.tap(find.text('Wall W-1').first);
    await tester.pump();
    await tester.tap(find.byTooltip(const S(true).xray));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('class-IfcWall')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('section-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('walk-toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('walk-hint')), findsOneWidget);
    expect(find.text('Column C-1'), findsNothing);

    await tester.tap(find.byTooltip(const S(true).actions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(const S(true).savedViews));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('named-view-save')));
    await tester.pump();
    expect(find.text(const S(true).savedViewEmpty), findsOneWidget);

    await tester.enterText(find.byKey(const Key('named-view-name')), 'Стены');
    await tester.tap(find.byKey(const Key('named-view-save')));
    await tester.pump();
    expect(find.text('Стены'), findsOneWidget);
    await tester.tap(find.text(const S(true).cancel));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(const S(true).actions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(const S(true).showAll));
    await tester.pump();
    expect(find.text('Column C-1'), findsOneWidget);
    expect(find.byKey(const ValueKey('walk-hint')), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('section-toggle')))
          .isSelected,
      isFalse,
    );

    await tester.tap(find.byTooltip(const S(true).actions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(const S(true).savedViews));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Стены'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('walk-hint')), findsNothing);
    expect(find.text('Column C-1'), findsNothing);
    expect(find.text('Wall W-1'), findsWidgets);
    expect(
      tester
          .widget<FilterChip>(find.byKey(const ValueKey('class-IfcWall')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('section-toggle')))
          .isSelected,
      isTrue,
    );
    expect(_tool(tester, const S(true).xray).isSelected, isTrue);

    final sidecar = File('${copy.path}.views.json');
    final json = jsonDecode(sidecar.readAsStringSync()) as Map<String, Object?>;
    expect(json['kind'], 'fbv-views-1');
    final views = json['views'] as List<Object?>;
    final stored = views.single as Map<String, Object?>;
    expect(stored['name'], 'Стены');
    expect(stored['xray'], isTrue);
    final viewpoint = stored['viewpoint'] as Map<String, Object?>;
    expect(viewpoint['ifc_class'], 'IfcWall');
    expect((viewpoint['section'] as Map<String, Object?>)['enabled'], isTrue);
    expect(File('${copy.path}.remarks.json').existsSync(), isFalse);
    expect(
      File(p.join(copy.path, 'manifest.json')).readAsStringSync(),
      manifest,
    );
    expect(_packageListing(copy), before);
    expect(tester.takeException(), isNull);
  });
}

String _repoFile(String relative) =>
    p.normalize(p.join(Directory.current.path, '..', relative));

IconButton _tool(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(IconButton),
    ),
  );
}

List<String> _packageListing(Directory root) {
  final paths = [
    for (final entity in root.listSync(recursive: true, followLinks: false))
      p.relative(entity.path, from: root.path),
  ]..sort();
  return paths;
}

void _copyPackage(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(followLinks: false)) {
    final target = p.join(to.path, p.basename(entity.path));
    if (entity is Directory) {
      _copyPackage(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}
