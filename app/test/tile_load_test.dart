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

  test('a package without tiles keeps the whole model', () {
    expect(activeTile(tiles: const [], storeyId: 10, discipline: null), isNull);
    expect(tileDisciplines(tiles: const [], storeyId: null), isEmpty);
  });

  test(
    'no storey choice streams the first storey and its first discipline',
    () {
      final chosen = activeTile(tiles: tiles, storeyId: null, discipline: null);
      expect(chosen, isNotNull);
      expect(chosen!.tileId, 1);
      expect(chosen.elementIds, [1, 2]);
      expect(chosen.discipline, 'architecture');
      expect(tileDisciplines(tiles: tiles, storeyId: null), [
        'architecture',
        'ventilation',
      ]);
    },
  );

  test('a storey and discipline pick that one tile', () {
    final chosen = activeTile(
      tiles: tiles,
      storeyId: 10,
      discipline: 'ventilation',
    );
    expect(chosen!.tileId, 2);
    expect(chosen.elementIds, [3]);
    final other = activeTile(tiles: tiles, storeyId: 20, discipline: null);
    expect(other!.tileId, 3);
    expect(other.elementIds, [4, 5]);
  });

  test('an unknown discipline stays on the same storey', () {
    final chosen = activeTile(
      tiles: tiles,
      storeyId: 20,
      discipline: 'ventilation',
    );
    expect(chosen!.tileId, 3);
    expect(chosen.discipline, 'structure');
  });

  test('a missing storey falls back instead of every element', () {
    final chosen = activeTile(tiles: tiles, storeyId: 99, discipline: null);
    expect(chosen!.elementIds, isNot(contains(9)));
    expect(chosen.elementIds, [1, 2]);
  });
}
