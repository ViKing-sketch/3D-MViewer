import 'dart:io';

import 'package:field_bim_viewer/src/package_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('session reads quantities from the sample package', () async {
    final path = p.normalize(p.join(Directory.current.path, '..', 'testdata', 'sample_model'));
    final session = PackageSession.openPath(path);
    final elements = session.elements();
    final wall = elements.firstWhere((element) => element.name == 'Wall W-1');
    final quantities = session.quantities(wall.id);
    expect(quantities.map((q) => q.name), contains('Length'));
    final length = quantities.firstWhere((q) => q.name == 'Length');
    expect(length.value, closeTo(5, 1e-6));
    expect(length.unit, 'm');
    expect(length.kind, 'Length');
    final zip = p.normalize(p.join(Directory.current.path, '..', 'testdata', 'sample_wall.fbvpkg'));
    final zipped = PackageSession.openPath(zip);
    expect(zipped.summary.name, 'Sample Project');
    expect(zipped.elements().map((e) => e.name), contains('Slab S-1'));
    zipped.close();
    session.close();
  });
}
