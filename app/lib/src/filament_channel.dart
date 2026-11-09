import 'package:flutter/services.dart';

import 'walk_pose.dart';

/// Commands for one `fbv/filament` platform view.
///
/// The native view owns the camera gestures. Flutter sends selection,
/// visibility and the framed views from [docs/rendering.md].
class FilamentCommands {
  FilamentCommands(this.channel);

  final MethodChannel channel;

  Future<Map<String, dynamic>?> sync() async {
    final value = await channel.invokeMethod<dynamic>('sync');
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return null;
  }

  Future<void> load(String root) {
    return channel.invokeMethod<void>('load', {'root': root});
  }

  /// Drops the GPU scene, mapped files and the in-flight upload. The engine
  /// stays until the platform view is disposed.
  Future<void> release() {
    return channel.invokeMethod<void>('release');
  }

  Future<void> setViewState({
    required int? selectedId,
    required List<int> hidden,
    required List<int> isolated,
    required bool xray,
    bool frame = false,
  }) {
    return channel.invokeMethod<void>('setViewState', {
      'selected': selectedId ?? 0,
      'hidden': hidden,
      'isolated': isolated,
      'xray': xray,
      'frame': frame,
    });
  }

  Future<void> fit({required bool selected}) {
    return channel.invokeMethod<void>('fit', {'selected': selected});
  }

  Future<void> setCamera(String preset) {
    return channel.invokeMethod<void>('setCamera', {'preset': preset});
  }

  /// [WalkCommand.enabled] places the eye on a storey. Orbit leaves the
  /// current view where the last orbit or walk frame put it.
  Future<void> setNavigation(WalkCommand walk) {
    if (!walk.enabled) {
      return channel.invokeMethod<void>('setNavigation', {
        'mode': 'orbit',
        'token': walk.token,
      });
    }
    return channel.invokeMethod<void>('setNavigation', {
      'mode': 'walk',
      'token': walk.token,
      'eye': [walk.eyeX, walk.eyeY, walk.eyeZ],
      'look': [walk.lookX, walk.lookY, walk.lookZ],
    });
  }

  /// Fraction of the platform view covered from the bottom, usually by the sheet.
  Future<void> setFitInset(double bottom) {
    return channel.invokeMethod<void>('setFitInset', {'bottom': bottom});
  }

  /// Section clip. [SectionView.near] and [SectionView.offset] are normalised.
  /// The plane itself is solved on the native side in world metres.
  Future<void> setSection(SectionView section) {
    return channel.invokeMethod<void>('setSection', section.toJson());
  }

  /// Live orbit or walk eye, in Filament Y-up metres. Null when this target
  /// has no platform view.
  Future<FilamentCamera?> cameraPose() async {
    try {
      final value = await channel.invokeMethod<dynamic>('cameraPose');
      if (value is! Map) return null;
      final eye = _triple(value['eye']);
      final target = _triple(value['target']);
      if (eye == null || target == null) return null;
      final dx = target[0] - eye[0];
      final dy = target[1] - eye[1];
      final dz = target[2] - eye[2];
      if (dx * dx + dy * dy + dz * dz < 1e-8) return null;
      return FilamentCamera(eye: eye, target: target);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Places the orbit camera. [eye] and [target] are Filament Y-up.
  Future<void> setViewpoint({
    required List<double> eye,
    required List<double> target,
  }) {
    return channel.invokeMethod<void>('setViewpoint', {
      'eye': eye,
      'target': target,
    });
  }
}

class FilamentCamera {
  const FilamentCamera({required this.eye, required this.target});

  final List<double> eye;
  final List<double> target;
}

List<double>? _triple(Object? raw) {
  if (raw is! List || raw.length < 3) return null;
  final x = (raw[0] as num?)?.toDouble();
  final y = (raw[1] as num?)?.toDouble();
  final z = (raw[2] as num?)?.toDouble();
  if (x == null || y == null || z == null) return null;
  return [x, y, z];
}

/// Срез controls. [axis] is `x`, `y`, `z` or `view`.
///
/// [near] and [inset] run from 0 to 1. [offset] runs from -1 to 1.
/// Y is up in the viewer.
class SectionView {
  const SectionView({
    this.enabled = false,
    this.near = 0,
    this.axis = 'x',
    this.flip = false,
    this.offset = 0,
    this.box = false,
    this.inset = 0,
  });

  final bool enabled;
  final double near;
  final String axis;
  final bool flip;
  final double offset;
  final bool box;
  final double inset;

  SectionView copyWith({
    bool? enabled,
    double? near,
    String? axis,
    bool? flip,
    double? offset,
    bool? box,
    double? inset,
  }) {
    return SectionView(
      enabled: enabled ?? this.enabled,
      near: near ?? this.near,
      axis: axis ?? this.axis,
      flip: flip ?? this.flip,
      offset: offset ?? this.offset,
      box: box ?? this.box,
      inset: inset ?? this.inset,
    );
  }

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'near': near,
    'axis': axis,
    'flip': flip,
    'offset': offset,
    'box': box,
    'inset': inset,
  };

  @override
  bool operator ==(Object other) {
    return other is SectionView &&
        other.enabled == enabled &&
        other.near == near &&
        other.axis == axis &&
        other.flip == flip &&
        other.offset == offset &&
        other.box == box &&
        other.inset == inset;
  }

  @override
  int get hashCode =>
      Object.hash(enabled, near, axis, flip, offset, box, inset);
}
