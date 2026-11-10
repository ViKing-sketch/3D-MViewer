import 'dart:io';

import 'package:field_bim_viewer/src/model.dart';
import 'package:field_bim_viewer/src/package_session.dart';
import 'package:field_bim_viewer/src/walk_pose.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a slab floor stands outside the wall box at eye height', () {
    final pose = walkOnStorey(
      storeyId: 4,
      elevation: 0,
      boxes: const [
        ElementBox(
          id: 1,
          storeyId: 4,
          ifcClass: 'IfcWall',
          minX: 9997.5,
          minY: 19999.9,
          minZ: 0,
          maxX: 10002.5,
          maxY: 20000.1,
          maxZ: 3,
        ),
        ElementBox(
          id: 2,
          storeyId: 4,
          ifcClass: 'IfcColumn',
          minX: 10001.8,
          minY: 20000.8,
          minZ: 0,
          maxX: 10002.2,
          maxY: 20001.2,
          maxZ: 3,
        ),
        ElementBox(
          id: 3,
          storeyId: 4,
          ifcClass: 'IfcSlab',
          minX: 9997,
          minY: 19998,
          minZ: -0.2,
          maxX: 10003,
          maxY: 20002,
          maxZ: 0,
        ),
        ElementBox(
          id: 4,
          storeyId: 4,
          ifcClass: 'IfcBuildingElementProxy',
          minX: 0,
          minY: 0,
          minZ: 0,
          maxX: 0,
          maxY: 0,
          maxZ: 0,
        ),
      ],
    );
    expect(pose.floorZ, 0);
    expect(pose.eyeZ, kWalkEyeHeight);
    expect(pose.clearOfSolids, isTrue);
    expect(pose.eyeX, inInclusiveRange(9997, 10003));
    expect(pose.eyeY, inInclusiveRange(19998, 20002));
    expect(pose.eyeY, lessThan(19999.9 - kWalkClearance));
    expect(pose.lookY, greaterThan(0.9));
    expect(pose.lookX.abs(), lessThan(0.05));
    final eye = filamentWalk(pose, const [9997, 19998, -0.2]);
    expect(eye.eyeY, closeTo(kWalkEyeHeight - (-0.2), 1e-9));
    expect(eye.lookY, 0);
    expect(eye.lookZ, closeTo(-1, 1e-6));
  });

  test('a box that fills the footprint starts inside it', () {
    final pose = walkOnStorey(
      storeyId: 1,
      elevation: 3,
      boxes: const [
        ElementBox(
          id: 1,
          storeyId: 1,
          ifcClass: 'IfcWall',
          minX: 0,
          minY: 0,
          minZ: 3,
          maxX: 4,
          maxY: 4,
          maxZ: 6,
        ),
      ],
    );
    expect(pose.clearOfSolids, isFalse);
    expect(pose.eyeX, 2);
    expect(pose.eyeY, 2);
    expect(pose.eyeZ, 3 + kWalkEyeHeight);
    expect(pose.lookY, 1);
  });

  test('an empty storey stands at its elevation', () {
    final pose = walkOnStorey(storeyId: 9, elevation: 12, boxes: const []);
    expect(pose.eyeZ, 12 + kWalkEyeHeight);
    expect(pose.clearOfSolids, isTrue);
    expect(pose.eyeX, 0);
    expect(pose.eyeY, 0);
  });

  test('the filter storey wins over the selection', () {
    final nodes = [
      SpatialNode(
        id: 1,
        parentId: 0,
        kind: 'Storey',
        name: 'Low',
        hasElevation: true,
        elevation: 0,
      ),
      SpatialNode(
        id: 2,
        parentId: 0,
        kind: 'Storey',
        name: 'High',
        hasElevation: true,
        elevation: 3,
      ),
    ];
    expect(
      walkStorey(spatial: nodes, filterStoreyId: 2, selectedStoreyId: 1)?.id,
      2,
    );
    expect(
      walkStorey(
        spatial: nodes,
        filterStoreyId: null,
        selectedStoreyId: 1,
      )?.name,
      'Low',
    );
  });

  test('the sample package stand matches its slab and wall boxes', () {
    final path = p.normalize(
      p.join(Directory.current.path, '..', 'testdata', 'sample_model'),
    );
    final session = PackageSession.openPath(path);
    final pose = walkOnStorey(
      storeyId: 4,
      elevation: 0,
      boxes: session.elementBoxes(),
    );
    expect(pose.clearOfSolids, isTrue);
    expect(pose.eyeZ, kWalkEyeHeight);
    expect(pose.eyeY, lessThan(19999.9 - kWalkClearance));
    final eye = filamentWalk(pose, localOriginOf(session.manifest));
    expect(eye.eyeY, closeTo(1.8, 1e-9));
    expect(eye.lookZ, lessThan(0));
    session.close();
  });
}
