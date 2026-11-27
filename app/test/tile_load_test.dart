import 'package:field_bim_viewer/src/model.dart';
import 'package:field_bim_viewer/src/tile_load.dart';
import 'package:flutter_test/flutter_test.dart';

TileInfo tile(int id, int? storey, String discipline, List<int> elements) {
  return TileInfo(
    id: id,
    storeyId: storey,
    discipline: discipline,
    elementCount: elements.length,
    elementIds: elements,
  );
}

void main() {
  final tiles = [
    tile(1, 10, 'architecture', [1, 2]),
    tile(2, 10, 'ventilation', [3]),
    tile(3, 20, 'structure', [4, 5]),
    tile(4, null, '', [9]),
  ];

  Map<int, int> meshBytes() => {1: 6, 2: 6, 3: 4, 4: 4, 5: 4, 9: 1};

  test('a package without tiles keeps the whole model', () {
    expect(
      sceneTiles(tiles: const [], storeyId: 10, discipline: null),
      isNull,
    );
    expect(tileDisciplines(tiles: const [], storeyId: null), isEmpty);
    expect(tileOf(const [], 1), isNull);
  });

  test('all storeys loads every tile when the meshes fit', () {
    final scene = sceneTiles(
      tiles: tiles,
      storeyId: null,
      discipline: null,
      elementBytes: meshBytes(),
      budgetBytes: 100,
    );
    expect(scene, isNotNull);
    expect(scene!.tiles.map((item) => item.tileId), [1, 2, 3, 4]);
    expect(scene.elementIds, [1, 2, 3, 4, 5, 9]);
    expect(scene.omitted, 0);
    expect(tileDisciplines(tiles: tiles, storeyId: null), [
      'architecture',
      'structure',
      'ventilation',
      '',
    ]);
  });

  test('all storeys stops when the next tile does not fit', () {
    final scene = sceneTiles(
      tiles: tiles,
      storeyId: null,
      discipline: null,
      elementBytes: meshBytes(),
      budgetBytes: 20,
    );
    expect(scene!.tiles.map((item) => item.tileId), [1, 2]);
    expect(scene.elementIds, [1, 2, 3]);
    expect(scene.omitted, 2);
    expect(scene.partial, isTrue);
  });

  test('the first tile is kept even when it is larger than the budget', () {
    final scene = sceneTiles(
      tiles: tiles,
      storeyId: null,
      discipline: null,
      elementBytes: meshBytes(),
      budgetBytes: 10,
    );
    expect(scene!.tiles.map((item) => item.tileId), [1]);
    expect(scene.omitted, 3);
  });

  test('a discipline across all storeys stays inside that discipline', () {
    final scene = sceneTiles(
      tiles: tiles,
      storeyId: null,
      discipline: 'ventilation',
      elementBytes: meshBytes(),
      budgetBytes: 1,
    );
    expect(scene!.tiles.single.tileId, 2);
    expect(scene.elementIds, [3]);
    expect(scene.omitted, 0);
  });

  test('a chosen storey is one tile and does not report omitted tiles', () {
    final scene = sceneTiles(
      tiles: tiles,
      storeyId: 10,
      discipline: 'ventilation',
      elementBytes: meshBytes(),
      budgetBytes: 1,
    );
    expect(scene!.tiles.single.tileId, 2);
    expect(scene.omitted, 0);
    final other = sceneTiles(
      tiles: tiles,
      storeyId: 20,
      discipline: null,
      budgetBytes: 1,
    );
    expect(other!.elementIds, [4, 5]);
    expect(other.omitted, 0);
  });

  test('an unknown discipline or storey does not load every element', () {
    final scene = sceneTiles(
      tiles: tiles,
      storeyId: 20,
      discipline: 'ventilation',
    );
    expect(scene!.tiles.single.discipline, 'structure');
    final missing = sceneTiles(tiles: tiles, storeyId: 99, discipline: null);
    expect(missing!.elementIds, [1, 2]);
  });

  test('an element points at its own tile', () {
    expect(tileOf(tiles, 5)?.id, 3);
    expect(tileOf(tiles, 5)?.storeyId, 20);
    expect(tileOf(tiles, 5)?.discipline, 'structure');
    expect(tileOf(tiles, 9)?.id, 4);
    expect(tileOf(tiles, 8), isNull);
  });
}
