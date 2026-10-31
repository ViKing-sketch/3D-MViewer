import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final class FbvElementInfo extends Struct {
  @Int64()
  external int id;
  @Int64()
  external int storeyId;
  @Int64()
  external int parentId;
  @Int64()
  external int typeId;
  @Int32()
  external int meshNode;
  @Int32()
  external int hasBrep;
  @Int32()
  external int hasBbox;
  @Int32()
  external int pad;
  @Array(3)
  external Array<Double> bboxMin;
  @Array(3)
  external Array<Double> bboxMax;
  @Array(3)
  external Array<Float> color;
  @Float()
  external double colorPad;
  @Array(64)
  external Array<Uint8> guid;
  @Array(64)
  external Array<Uint8> ifcClass;
  @Array(256)
  external Array<Uint8> name;
  @Array(64)
  external Array<Uint8> tag;
  @Array(128)
  external Array<Uint8> typeName;
  @Array(128)
  external Array<Uint8> material;
}

void main() {
  test('fbv_core reads the sample package', () {
    final libPath = Platform.environment['FBV_CORE_LIB'];
    if (libPath == null || libPath.isEmpty) {
      markTestSkipped('FBV_CORE_LIB is not set');
      return;
    }
    final lib = DynamicLibrary.open(libPath);
    final abi = lib.lookupFunction<Int32 Function(), int Function()>('fbv_abi_element_size');
    expect(abi(), sizeOf<FbvElementInfo>());

    final open = lib.lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, IntPtr),
        Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, int)>('fbv_package_open');
    final close = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'fbv_package_close',
    );
    final count = lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'fbv_element_count',
    );
    final byId = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Int64, Pointer<FbvElementInfo>),
        int Function(Pointer<Void>, int, Pointer<FbvElementInfo>)>('fbv_element_by_id');

    final sample = p.normalize(p.join(Directory.current.path, '..', 'testdata', 'sample_model'));
    final pathPtr = sample.toNativeUtf8();
    final err = calloc<Uint8>(512);
    final package = open(pathPtr, err.cast(), 512);
    calloc.free(pathPtr);
    expect(package, isNot(nullptr), reason: err.cast<Utf8>().toDartString());
    expect(count(package), 4);
    final info = calloc<FbvElementInfo>();
    expect(byId(package, 1, info), 0);
    expect(info.ref.id, 1);
    expect(info.ref.ifcClass[0], 0x49); // 'I' of IfcWall
    calloc.free(info);
    close(package);
    calloc.free(err);
  });
}
