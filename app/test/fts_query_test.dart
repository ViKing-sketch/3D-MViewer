import 'package:field_bim_viewer/src/fts_query.dart';
import 'package:field_bim_viewer/src/package_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:path/path.dart' as p;

void main() {
  test('fts expression quotes a hyphenated mark and joins words', () {
    expect(ftsMatchExpression('  '), isNull);
    expect(ftsMatchExpression('НС-12'), '"НС-12"*');
    expect(ftsMatchExpression('LoadBearing true'), '"LoadBearing"* "true"*');
    expect(ftsMatchExpression('say "hi"'), '"say"* """hi"""*');
  });

  test(
    'sample package search finds a property that is not the element name',
    () {
      final path = p.normalize(
        p.join(Directory.current.path, '..', 'testdata', 'sample_model'),
      );
      final session = PackageSession.openPath(path);
      expect(session.searchIds('НС-12'), [1]);
      expect(session.searchIds('Column'), [2]);
      expect(session.searchIds('0Yvh4\$d\$H4PgX8k1\$f\$x22'), [3]);
      expect(session.searchIds('no-such-value-zz'), isEmpty);
      expect(session.searchIds('   '), isEmpty);
      session.close();
    },
  );
}
