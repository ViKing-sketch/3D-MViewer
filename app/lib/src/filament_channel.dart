import 'package:flutter/services.dart';

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

  /// Fraction of the platform view covered from the bottom, usually by the sheet.
  Future<void> setFitInset(double bottom) {
    return channel.invokeMethod<void>('setFitInset', {'bottom': bottom});
  }

  /// Section clip. [SectionView.near] and [SectionView.offset] are normalised.
  /// The plane itself is solved on the native side in world metres.
  Future<void> setSection(SectionView section) {
    return channel.invokeMethod<void>('setSection', section.toJson());
  }
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
    this.inset = 0.25,
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
  int get hashCode => Object.hash(enabled, near, axis, flip, offset, box, inset);
}
