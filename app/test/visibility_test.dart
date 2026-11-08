import 'package:field_bim_viewer/src/model.dart';
import 'package:field_bim_viewer/src/visibility.dart';
import 'package:flutter_test/flutter_test.dart';

ElementInfo element({
  required int id,
  required int storeyId,
  required String ifcClass,
  String material = '',
  String name = '',
}) {
  return ElementInfo(
    id: id,
    parentId: storeyId,
    storeyId: storeyId,
    ifcClass: ifcClass,
    name: name,
    tag: '',
    typeName: '',
    material: material,
    guid: '$id',
  );
}

void main() {
  final wall = element(
    id: 1,
    storeyId: 4,
    ifcClass: 'IfcWall',
    material: 'Бетон',
    name: 'Wall',
  );
  final column = element(
    id: 2,
    storeyId: 4,
    ifcClass: 'IfcColumn',
    material: 'Concrete',
    name: 'Column',
  );
  final roof = element(
    id: 3,
    storeyId: 9,
    ifcClass: 'IfcSlab',
    material: 'Concrete',
    name: 'Roof',
  );
  final marker = element(
    id: 4,
    storeyId: 0,
    ifcClass: 'IfcBuildingElementProxy',
    name: 'Marker',
  );
  final elements = [wall, column, roof, marker];

  test('storeys sort by elevation then name', () {
    final nodes = [
      SpatialNode(
        id: 9,
        parentId: 1,
        kind: 'Storey',
        name: 'Roof',
        hasElevation: true,
        elevation: 6,
      ),
      SpatialNode(
        id: 2,
        parentId: 1,
        kind: 'Building',
        name: 'Building',
        hasElevation: false,
        elevation: 0,
      ),
      SpatialNode(
        id: 5,
        parentId: 1,
        kind: 'Storey',
        name: 'Level 1',
        hasElevation: true,
        elevation: 0,
      ),
      SpatialNode(
        id: 6,
        parentId: 1,
        kind: 'Storey',
        name: 'Level 1b',
        hasElevation: true,
        elevation: 0,
      ),
    ];
    expect(storeysOf(nodes).map((node) => node.id).toList(), [5, 6, 9]);
  });

  test('filters combine and a blank material is its own value', () {
    const level = SceneFilter(storeyId: 4);
    expect(level.matches(wall), isTrue);
    expect(level.matches(roof), isFalse);
    expect(level.matches(marker), isFalse);

    const concrete = SceneFilter(storeyId: 4, material: 'Concrete');
    expect(concrete.matches(column), isTrue);
    expect(concrete.matches(wall), isFalse);
    expect(concrete.matches(roof), isFalse);

    const blank = SceneFilter(material: '');
    expect(blank.matches(marker), isTrue);
    expect(blank.matches(wall), isFalse);
    expect(materialsOf(elements), ['', 'Concrete', 'Бетон']);
  });

  test('viewer hide unions the manual set with the filter', () {
    final hidden = viewerHidden(
      elements: elements,
      filter: const SceneFilter(ifcClass: 'IfcWall'),
      hidden: {3},
    );
    expect(hidden, {2, 3, 4});
    expect(
      viewerHidden(
        elements: elements,
        filter: const SceneFilter(),
        hidden: {3},
      ),
      {3},
    );
  });

  test('isolate drops elements the filter rejects', () {
    expect(isolateWithin({1, 3}, elements, const SceneFilter(storeyId: 4)), {
      1,
    });
    expect(isolateWithin({1, 3}, elements, const SceneFilter()), {1, 3});
    expect(isolateWithin({99}, elements, const SceneFilter()), isEmpty);
  });
}
