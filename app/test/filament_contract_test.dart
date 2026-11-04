import 'dart:io';

import 'package:field_bim_viewer/src/filament_channel.dart';
import 'package:field_bim_viewer/src/glb_ids.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sample glbs store extras.elementId in the JSON chunk', () {
    final root = Directory(
      p.normalize(
        p.join(
          Directory.current.path,
          '..',
          'testdata',
          'sample_model',
          'mesh',
        ),
      ),
    );
    expect(glbElementIds(_bytes(File(p.join(root.path, 'lod0.glb')))), [
      1,
      2,
      3,
    ]);
    expect(
      glbElementIds(_bytes(File(p.join(root.path, 'elements', '1.glb')))),
      [1],
    );
    expect(
      glbElementIds(_bytes(File(p.join(root.path, 'elements', '2.glb')))),
      [2],
    );
    final binOnly = Uint8List(40);
    expect(glbElementIds(binOnly), isEmpty);
  });

  test('filament commands encode selection and visibility', () async {
    const channel = MethodChannel('fbv/filament/test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'sync') {
            return {
              'code': 'ready',
              'lod0': true,
              'elementFiles': 3,
              'drawn': 3,
            };
          }
          return null;
        });
    final commands = FilamentCommands(channel);
    final status = await commands.sync();
    expect(status?['elementFiles'], 3);
    await commands.setViewState(
      selectedId: 2,
      hidden: const [1],
      isolated: const [2],
      xray: true,
    );
    await commands.setSection(
      const SectionView(
        enabled: true,
        near: 0.4,
        axis: 'view',
        flip: true,
        offset: -0.25,
        box: true,
        inset: 0.3,
      ),
    );
    await commands.fit(selected: true);
    await commands.setCamera('top');
    await commands.release();
    expect(calls.map((call) => call.method).toList(), [
      'sync',
      'setViewState',
      'setSection',
      'fit',
      'setCamera',
      'release',
    ]);
    final view = calls[1].arguments as Map<dynamic, dynamic>;
    expect(view['selected'], 2);
    expect(view['hidden'], [1]);
    expect(view['isolated'], [2]);
    expect(view['xray'], isTrue);
    expect(view['frame'], isFalse);
    final section = calls[2].arguments as Map<dynamic, dynamic>;
    expect(section['enabled'], isTrue);
    expect(section['near'], 0.4);
    expect(section['axis'], 'view');
    expect(section['flip'], isTrue);
    expect(section['offset'], -0.25);
    expect(section['box'], isTrue);
    expect(section['inset'], 0.3);
    expect((calls[3].arguments as Map)['selected'], isTrue);
    expect((calls[4].arguments as Map)['preset'], 'top');
  });
}

Uint8List _bytes(File file) => Uint8List.fromList(file.readAsBytesSync());
