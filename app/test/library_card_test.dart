import 'dart:io';

import 'package:field_bim_viewer/src/model.dart';
import 'package:field_bim_viewer/src/package_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a missing manifest date uses the package file time', () {
    final file = File(
      p.join(
        Directory.systemTemp.path,
        'fbv-date-${DateTime.now().microsecondsSinceEpoch}.txt',
      ),
    );
    file.writeAsStringSync('x');
    file.setLastModifiedSync(DateTime.utc(2024, 1, 2, 3, 4, 5));
    addTearDown(file.deleteSync);
    expect(libraryDateLabel(packageCreated(const {}, file.path)), '2024-01-02');
    expect(
      libraryDateLabel(
        packageCreated(const {
          'created_utc': '2026-10-31T10:46:54Z',
        }, file.path),
      ),
      '2026-10-31',
    );
  });

  test('the sample list shows the manifest day and skips an empty box', () {
    final root = p.normalize(p.join(Directory.current.path, '..', 'testdata'));
    final cards = scanLibrary(root);
    final projects = cards.where((card) => card.name == 'Sample Project');
    expect(projects, hasLength(2));
    for (final card in projects) {
      expect(libraryDateLabel(card.createdUtc), '2026-10-31');
      expect(card.plan, hasLength(3));
      expect(
        card.plan.every((box) => (box.maxX - box.minX).abs() > 1e-4),
        isTrue,
      );
    }
    final wall = projects.first.plan.firstWhere(
      (box) => (box.maxY - box.minY) < 0.5,
    );
    expect(wall.red, closeTo(0.8, 1e-6));
    expect(wall.green, closeTo(0.78, 1e-6));
    expect(wall.blue, closeTo(0.7, 1e-6));
  });
}
