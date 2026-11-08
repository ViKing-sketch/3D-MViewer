import 'model.dart';

/// Storey, IFC class and material limits for the tree and the 3D scene.
///
/// A null field means that dimension is not limited. An empty [material] is a
/// real value: elements whose package material is blank. Engineering systems
/// are not a field here. format_version 1 does not store IfcSystem membership.
class SceneFilter {
  const SceneFilter({this.storeyId, this.ifcClass, this.material});

  final int? storeyId;
  final String? ifcClass;
  final String? material;

  bool get active => storeyId != null || ifcClass != null || material != null;

  bool matches(ElementInfo element) {
    if (storeyId != null && element.storeyId != storeyId) return false;
    if (ifcClass != null && element.ifcClass != ifcClass) return false;
    if (material != null && element.material != material) return false;
    return true;
  }

  SceneFilter copyWith({
    int? storeyId,
    String? ifcClass,
    String? material,
    bool clearStorey = false,
    bool clearClass = false,
    bool clearMaterial = false,
  }) {
    return SceneFilter(
      storeyId: clearStorey ? null : (storeyId ?? this.storeyId),
      ifcClass: clearClass ? null : (ifcClass ?? this.ifcClass),
      material: clearMaterial ? null : (material ?? this.material),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SceneFilter &&
        other.storeyId == storeyId &&
        other.ifcClass == ifcClass &&
        other.material == material;
  }

  @override
  int get hashCode => Object.hash(storeyId, ifcClass, material);
}

/// Storeys in elevation order, then name, then id.
List<SpatialNode> storeysOf(Iterable<SpatialNode> spatial) {
  final storeys = [
    for (final node in spatial)
      if (node.kind == 'Storey') node,
  ];
  storeys.sort((a, b) {
    final byElevation = a.elevation.compareTo(b.elevation);
    if (byElevation != 0) return byElevation;
    final byName = a.name.compareTo(b.name);
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  });
  return storeys;
}

/// Distinct material strings, including blank, in code-unit order.
List<String> materialsOf(Iterable<ElementInfo> elements) {
  final names = {for (final element in elements) element.material}.toList();
  names.sort();
  return names;
}

/// Ids the viewer must hide: the manual set plus anything outside [filter].
Set<int> viewerHidden({
  required Iterable<ElementInfo> elements,
  required SceneFilter filter,
  required Set<int> hidden,
}) {
  final out = <int>{...hidden};
  if (!filter.active) return out;
  for (final element in elements) {
    if (!filter.matches(element)) out.add(element.id);
  }
  return out;
}

/// Isolate stays inside the filter. Ids the filter rejects are dropped.
Set<int> isolateWithin(
  Set<int> isolated,
  Iterable<ElementInfo> elements,
  SceneFilter filter,
) {
  final out = <int>{};
  for (final id in isolated) {
    for (final element in elements) {
      if (element.id == id && filter.matches(element)) {
        out.add(id);
        break;
      }
    }
  }
  return out;
}
