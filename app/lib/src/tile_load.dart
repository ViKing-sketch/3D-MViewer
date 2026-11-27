import 'model.dart';

/// Smaller device budget already used by the Android viewer (96 MiB).
/// «Все этажи» does not ask the scene for more than that.
const tileSceneBudgetBytes = 96 * 1024 * 1024;

/// One storey × discipline tile.
class ActiveTile {
  const ActiveTile({
    required this.tileId,
    required this.storeyId,
    required this.discipline,
    required this.elementIds,
  });

  final int tileId;
  final int? storeyId;
  final String discipline;
  final List<int> elementIds;
}

/// Tiles the scene should open.
///
/// [omitted] is how many candidate tiles did not fit [budgetBytes]. A chosen
/// storey is always one tile, so [omitted] is then zero.
class TileScene {
  const TileScene({
    required this.tiles,
    required this.elementIds,
    required this.omitted,
  });

  final List<ActiveTile> tiles;
  final List<int> elementIds;
  final int omitted;

  bool get partial => omitted > 0;
}

/// The tile that contains [elementId], if the package has one.
TileInfo? tileOf(List<TileInfo> tiles, int elementId) {
  for (final tile in tiles) {
    if (tile.elementIds.contains(elementId)) return tile;
  }
  return null;
}

/// [storeyId] null is «Все этажи»: tiles in storey order until [budgetBytes].
/// The first tile is kept even when it alone is larger than the budget.
/// A chosen storey is one tile (its [discipline], or the first on that storey).
/// A package with no tiles returns null and the viewer keeps the whole model.
TileScene? sceneTiles({
  required List<TileInfo> tiles,
  int? storeyId,
  String? discipline,
  Map<int, int> elementBytes = const {},
  int budgetBytes = tileSceneBudgetBytes,
}) {
  if (tiles.isEmpty) return null;
  if (storeyId != null) {
    final one = _oneTile(tiles, storeyId, discipline);
    if (one == null) return null;
    return TileScene(tiles: [one], elementIds: one.elementIds, omitted: 0);
  }
  final pool = _ordered(_matchingDiscipline(_allStoreys(tiles), discipline));
  if (pool.isEmpty) return null;
  final chosen = <TileInfo>[];
  var used = 0;
  for (final tile in pool) {
    final bytes = _tileBytes(tile, elementBytes);
    if (chosen.isNotEmpty && used + bytes > budgetBytes) break;
    chosen.add(tile);
    used += bytes;
  }
  final ids = <int>[for (final tile in chosen) ...tile.elementIds];
  return TileScene(
    tiles: [for (final tile in chosen) _active(tile)],
    elementIds: ids,
    omitted: pool.length - chosen.length,
  );
}

/// Disciplines on [storeyId]. Null [storeyId] lists every discipline.
List<String> tileDisciplines({required List<TileInfo> tiles, int? storeyId}) {
  final pool = storeyId == null
      ? tiles
      : tiles.where((tile) => tile.storeyId == storeyId).toList();
  final names = <String>{for (final tile in pool) tile.discipline};
  final listed = names.toList()
    ..sort((a, b) {
      if (a.isEmpty && b.isEmpty) return 0;
      if (a.isEmpty) return 1;
      if (b.isEmpty) return -1;
      return a.compareTo(b);
    });
  return listed;
}

ActiveTile? _oneTile(List<TileInfo> tiles, int storeyId, String? discipline) {
  final onStorey = tiles.where((tile) => tile.storeyId == storeyId).toList();
  final pool = onStorey.isEmpty ? tiles : onStorey;
  final named = _matchingDiscipline(pool, discipline);
  if (named.isEmpty) return null;
  return _active(_ordered(named).first);
}

List<TileInfo> _allStoreys(List<TileInfo> tiles) {
  final withStorey = tiles.where((tile) => tile.storeyId != null).toList();
  if (withStorey.isEmpty) return tiles;
  final rest = tiles.where((tile) => tile.storeyId == null);
  return [...withStorey, ...rest];
}

List<TileInfo> _matchingDiscipline(List<TileInfo> tiles, String? discipline) {
  if (discipline == null) return tiles;
  final matched = tiles.where((tile) => tile.discipline == discipline).toList();
  if (matched.isEmpty) return tiles;
  return matched;
}

List<TileInfo> _ordered(List<TileInfo> tiles) {
  final copy = [...tiles];
  copy.sort((a, b) {
    final storey = (a.storeyId ?? 1 << 30).compareTo(b.storeyId ?? 1 << 30);
    if (storey != 0) return storey;
    return a.id.compareTo(b.id);
  });
  return copy;
}

int _tileBytes(TileInfo tile, Map<int, int> elementBytes) {
  var sum = 0;
  for (final id in tile.elementIds) {
    sum += elementBytes[id] ?? 0;
  }
  return sum;
}

ActiveTile _active(TileInfo tile) {
  return ActiveTile(
    tileId: tile.id,
    storeyId: tile.storeyId,
    discipline: tile.discipline,
    elementIds: tile.elementIds,
  );
}
