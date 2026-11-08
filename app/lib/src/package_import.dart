import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android SAF import and share-intent delivery.
///
/// The native side copies the content URI into application storage and returns
/// that path. Desktop builds keep the typed folder field.
class PackageImport {
  PackageImport._();

  static const channel = MethodChannel('fbv/import');
  static void Function(String path)? _onOpened;
  static void Function(String message)? _onFailed;
  static String? _lastPath;
  static DateTime? _lastAt;

  static void bind({
    required void Function(String path) onOpened,
    void Function(String message)? onFailed,
  }) {
    _onOpened = onOpened;
    _onFailed = onFailed;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onOpened') {
        final path = call.arguments?.toString() ?? '';
        if (path.isNotEmpty) _deliver(path);
      } else if (call.method == 'onFailed') {
        _onFailed?.call(call.arguments?.toString() ?? '');
      }
      return null;
    });
  }

  static void _deliver(String path) {
    final now = DateTime.now();
    if (_lastPath == path &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastPath = path;
    _lastAt = now;
    _onOpened?.call(path);
  }

  static Future<String?> libraryDirectory() async {
    if (!Platform.isAndroid) return null;
    return channel.invokeMethod<String>('libraryDir');
  }

  static Future<String?> pick() async {
    if (!Platform.isAndroid) return null;
    return channel.invokeMethod<String>('pick');
  }

  /// Android system document picker. Other platforms return null; the page
  /// asks for a folder instead.
  static Future<String?> saveCsv({
    required String name,
    required String text,
  }) async {
    if (!Platform.isAndroid) return null;
    return channel.invokeMethod<String>('saveCsv', {
      'name': name,
      'text': text,
    });
  }

  static Future<String?> takePending() async {
    if (!Platform.isAndroid) return null;
    final path = await channel.invokeMethod<String>('takePending');
    if (path == null || path.isEmpty) return null;
    _lastPath = path;
    _lastAt = DateTime.now();
    return path;
  }
}
