import 'dart:convert';
import 'dart:ui';

import 'package:dodam/features/drawing/application/drawing_pressure_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// S15P11B209-481 — 필압 측정 정책의 포인터 종류·범위·비정상 값 계약을 고정한다.
///
/// Backend 계약은 0..1 nullable이고, Flutter 계약은 "1.0 = 보통 압력,
/// pressureMin ≤ 1.0 ≤ pressureMax"다. 선형 정규화 없이 포화(clamp)만 하는
/// 것이 이 정책의 의도이므로 그 의미까지 여기서 검증한다.
void main() {
  double? resolve({
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    double pressure = 0.4,
    double pressureMin = 0.0,
    double pressureMax = 1.0,
  }) => DrawingPressurePolicy.resolve(
    kind: kind,
    pressure: pressure,
    pressureMin: pressureMin,
    pressureMax: pressureMax,
  );

  group('포인터 종류', () {
    test('stylus는 측정한 필압을 그대로 전달한다', () {
      expect(resolve(kind: PointerDeviceKind.stylus, pressure: 0.4), 0.4);
    });

    test('invertedStylus도 필압 입력으로 인정한다', () {
      expect(
        resolve(kind: PointerDeviceKind.invertedStylus, pressure: 0.75),
        0.75,
      );
    });

    // 손가락·마우스류는 기기가 1.0을 고정 반환하므로 가짜 필압을 만들지 않는다.
    for (final kind in [
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
      PointerDeviceKind.unknown,
    ]) {
      test('$kind는 유효 범위가 보고돼도 null이다', () {
        expect(
          resolve(kind: kind, pressure: 0.6, pressureMin: 0, pressureMax: 1),
          isNull,
        );
      });
    }
  });

  group('범위와 기기 guard', () {
    test('0.0은 "압력 없음"이라는 유효한 측정값이며 null로 바꾸지 않는다', () {
      final resolved = resolve(pressure: 0.0);
      expect(resolved, 0.0);
      expect(resolved, isNotNull);
    });

    test('1.0(보통 압력)은 그대로 전달한다', () {
      expect(resolve(pressure: 1.0), 1.0);
    });

    test('0 미만은 0.0으로 포화한다', () {
      expect(resolve(pressure: -0.1), 0.0);
    });

    test('1.0 초과 강한 압력은 Backend 계약 상한 1.0으로 포화한다', () {
      expect(resolve(pressure: 1.25, pressureMax: 1.3), 1.0);
    });

    test('pressureMin == pressureMax는 필압 미지원 기기 보고로 보고 null이다', () {
      expect(
        resolve(pressure: 1.0, pressureMin: 1.0, pressureMax: 1.0),
        isNull,
      );
    });

    test('pressureMax < pressureMin(역전 범위)도 null이다', () {
      expect(
        resolve(pressure: 0.5, pressureMin: 1.0, pressureMax: 0.5),
        isNull,
      );
    });
  });

  group('non-finite 방어', () {
    test('pressure NaN은 null이다', () {
      expect(resolve(pressure: double.nan), isNull);
    });

    test('pressure +Infinity는 null이다', () {
      expect(resolve(pressure: double.infinity), isNull);
    });

    test('pressure -Infinity는 null이다', () {
      expect(resolve(pressure: double.negativeInfinity), isNull);
    });

    test('pressureMin이 non-finite면 null이다', () {
      expect(resolve(pressureMin: double.nan), isNull);
      expect(resolve(pressureMin: double.negativeInfinity), isNull);
    });

    test('pressureMax가 non-finite면 null이다', () {
      expect(resolve(pressureMax: double.nan), isNull);
      expect(resolve(pressureMax: double.infinity), isNull);
    });

    test('정책을 통과한 값은 항상 JSON으로 직렬화할 수 있다', () {
      for (final pressure in [
        double.nan,
        double.infinity,
        -5.0,
        0.0,
        0.7,
        9.9,
      ]) {
        final resolved = resolve(pressure: pressure, pressureMax: 1.3);
        // null이거나 0..1 finite — jsonEncode가 예외 없이 처리해야 한다.
        expect(jsonEncode({'pressure': resolved}), isA<String>());
        if (resolved != null) {
          expect(resolved, inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });
}
