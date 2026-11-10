import 'package:flutter/services.dart';

// Android loads libocct_probe_jni.so from nativeLibraryDir. Desktop and tests
// have no such library; the call fails and the library page shows the error.
class OcctProbeChannel {
  static const _channel = MethodChannel('fbv/occt');

  static Future<String> run() async {
    final text = await _channel.invokeMethod<String>('probe');
    return text ?? '';
  }
}
