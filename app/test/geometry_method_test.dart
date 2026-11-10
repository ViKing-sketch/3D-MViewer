import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_bim_viewer/src/geometry_method.dart';
import 'package:field_bim_viewer/src/model.dart';
import 'package:field_bim_viewer/src/strings.dart';

GeometryFacts _facts({
  int formatVersion = 4,
  int exactBytes = 100,
  bool abiSupported = true,
  bool jniLoaded = true,
  bool readOk = true,
  int elapsedMs = 10,
}) {
  return GeometryFacts(
    formatVersion: formatVersion,
    exactBytes: exactBytes,
    abiSupported: abiSupported,
    jniLoaded: jniLoaded,
    readOk: readOk,
    elapsedMs: elapsedMs,
  );
}

void main() {
  test('exact BinTools is chosen only when every check passes', () {
    final decision = decideGeometry(_facts());
    expect(decision.method, GeometryMethod.exact);
    expect(decision.reason, 'bintools');
    expect(decision.logLine, 'geometry method=exact reason=bintools');
  });

  test('versions 1, 2 and 3 stay on the mesh', () {
    for (final version in [1, 2, 3]) {
      final decision = decideGeometry(_facts(formatVersion: version));
      expect(decision.method, GeometryMethod.mesh);
      expect(decision.reason, 'old-package');
    }
  });

  test('an empty v4 slot and a missing file stay on the mesh', () {
    expect(decideGeometry(_facts(exactBytes: 0)).reason, 'no-bytes');
    expect(
      meshBeforeOcct(
        formatVersion: 4,
        rows: const [],
        root: '/tmp',
        abiSupported: true,
      )?.reason,
      'no-bytes',
    );
  });

  test(
    'JNI, ABI, read, memory and time each fall back without selecting exact',
    () {
      expect(decideGeometry(_facts(abiSupported: false)).reason, 'abi');
      expect(decideGeometry(_facts(jniLoaded: false)).reason, 'jni');
      expect(decideGeometry(_facts(readOk: false)).reason, 'read');
      expect(
        decideGeometry(_facts(exactBytes: kExactByteLimit + 1)).reason,
        'memory',
      );
      expect(
        decideGeometry(_facts(elapsedMs: kExactTimeLimitMs + 1)).reason,
        'time',
      );
    },
  );

  test('analytic AABB bytes are not an exact source', () {
    const row = ExactGeometry(elementId: 1, path: 'brep.pack', bytes: 0);
    expect(exactByteTotal(const [row]), 0);
    expect(decideGeometry(_facts(exactBytes: 0)).method, GeometryMethod.mesh);
  });

  test('a probe failure line maps onto the same mesh reasons', () {
    expect(decisionFromProbe('read=fail reason=jni\n').reason, 'jni');
    expect(
      decisionFromProbe('read=fail reason=memory bytes=9\n').reason,
      'memory',
    );
    expect(
      decisionFromProbe('read=fail reason=time elapsed_ms=9\n').reason,
      'time',
    );
    expect(decisionFromProbe('read=fail reason=read\n').reason, 'read');
    expect(
      decisionFromProbe('read=ok bytes=4 elapsed_ms=3\n').method,
      GeometryMethod.exact,
    );
    expect(
      decisionFromProbe(
        'read=ok bytes=4 elapsed_ms=${kExactTimeLimitMs + 5}\n',
      ).reason,
      'time',
    );
  });

  testWidgets('the banner names the method', (tester) async {
    const decision = GeometryDecision(
      method: GeometryMethod.mesh,
      reason: 'old-package',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GeometryMethodBanner(
          decision: decision,
          label: const S(
            true,
          ).geometryMethod(decision.method.name, decision.reason),
        ),
      ),
    );
    expect(find.text('Геометрия: меш (old-package)'), findsOneWidget);
    expect(find.byKey(const ValueKey('geometry-method')), findsOneWidget);
  });
}
