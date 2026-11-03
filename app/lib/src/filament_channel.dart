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
    if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
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
  }) {
    return channel.invokeMethod<void>('setViewState', {
      'selected': selectedId ?? 0,
      'hidden': hidden,
      'isolated': isolated,
      'xray': xray,
    });
  }

  Future<void> fit({required bool selected}) {
    return channel.invokeMethod<void>('fit', {'selected': selected});
  }

  Future<void> setCamera(String preset) {
    return channel.invokeMethod<void>('setCamera', {'preset': preset});
  }
}
