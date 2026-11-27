import 'model.dart';

/// The one storey × discipline tile the viewer streams into the scene.
///
/// A package with no tiles has no [ActiveTile]: the viewer keeps the whole
/// model. A package with tiles never asks for every mesh at once.
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

/// [storeyId] null means the user has not picked a storey, so the first
/// storey that has a tile is used. [discipline] null keeps the first
/// discipline of that storey. An unknown discipline falls back the same way.
ActiveTile? activeTile({
  required List<TileInfo> tiles,
  int? storeyId,
  String? discipline,
}) {
  if (tiles.isEmpty) return null;
  final onStorey = _onStorey(tiles, storeyId);
  if (onStorey.isEmpty) return null;
  final pool = _withDiscipline(onStorey, discipline);
  final tile = pool.reduce((a, b) => a.id <= b.id ? a : b);
  return ActiveTile(
    tileId: tile.id,
    storeyId: tile.storeyId,
    discipline: tile.discipline,
    elementIds: tile.elementIds,
  );
}

/// Disciplines present on [storeyId], or on the storey [activeTile] would
/// pick when [storeyId] is null. Empty disciplines stay in the list.
List<String> tileDisciplines({required List<TileInfo> tiles, int? storeyId}) {
  final onStorey = _onStorey(tiles, storeyId);
  final names = <String>{for (final tile in onStorey) tile.discipline};
  final listed = names.toList()
    ..sort((a, b) {
      if (a.isEmpty) return 1;
      if (b.isEmpty) return -1;
      return a.compareTo(b);
    });
  return listed;
}

List<TileInfo> _onStorey(List<TileInfo> tiles, int? storeyId) {
  if (tiles.isEmpty) return const [];
  if (storeyId != null) {
    final matched = tiles.where((tile) => tile.storeyId == storeyId).toList();
    if (matched.isNotEmpty) return matched;
  }
  final withStorey = tiles.where((tile) => tile.storeyId != null).toList();
  final pool = withStorey.isEmpty ? tiles : withStorey;
  var first = pool.first.storeyId;
  for (final tile in pool) {
    final id = tile.storeyId;
    if (first == null || (id != null && id < first)) first = id;
  }
  return pool.where((tile) => tile.storeyId == first).toList();
}

List<TileInfo> _withDiscipline(List<TileInfo> tiles, String? discipline) {
  if (discipline == null) return tiles;
  final matched = tiles.where((tile) => tile.discipline == discipline).toList();
  if (matched.isEmpty) return tiles;
  return matched;
}
