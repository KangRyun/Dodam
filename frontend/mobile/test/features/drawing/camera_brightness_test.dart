import 'dart:typed_data';

import 'package:dodam/features/drawing/application/camera_brightness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('averageLumaFromYPlane', () {
    test('빈 plane은 0을 돌려준다', () {
      expect(averageLumaFromYPlane(Uint8List(0)), 0);
    });

    test('균일한 값의 평균을 그대로 돌려준다', () {
      final plane = Uint8List.fromList(List.filled(1000, 40));
      expect(averageLumaFromYPlane(plane), 40);
    });

    test('stride로 서브샘플링해도 대략적인 평균을 유지한다', () {
      final plane = Uint8List.fromList(List.generate(1000, (i) => i % 2 * 200));
      final avg = averageLumaFromYPlane(plane, stride: 2);
      // stride 2는 같은 위상만 뽑으므로 0 또는 200에 수렴한다 — 유한하고 범위 안.
      expect(avg, inInclusiveRange(0, 200));
    });
  });

  group('BrightnessClassifier 히스테리시스', () {
    test('임계값 미만은 어두움, 초과는 밝음, 사이는 적정', () {
      expect(BrightnessClassifier().classify(30), CaptureBrightness.tooDark);
      expect(BrightnessClassifier().classify(130), CaptureBrightness.ok);
      expect(BrightnessClassifier().classify(240), CaptureBrightness.tooBright);
    });

    test('어두움에서 벗어나려면 임계값+여유를 넘어야 한다', () {
      final classifier = BrightnessClassifier();
      expect(classifier.classify(30), CaptureBrightness.tooDark);
      // 임계값(65) 바로 위로는 아직 유지된다.
      expect(
        classifier.classify(kDarkLumaThreshold + 1),
        CaptureBrightness.tooDark,
      );
      // 여유값을 넘으면 적정으로 복귀한다.
      expect(
        classifier.classify(kDarkLumaThreshold + kBrightnessHysteresis + 1),
        CaptureBrightness.ok,
      );
    });

    test('밝음에서 벗어나려면 임계값-여유 아래로 내려가야 한다', () {
      final classifier = BrightnessClassifier();
      expect(classifier.classify(240), CaptureBrightness.tooBright);
      expect(
        classifier.classify(kBrightLumaThreshold - 1),
        CaptureBrightness.tooBright,
      );
      expect(
        classifier.classify(kBrightLumaThreshold - kBrightnessHysteresis - 1),
        CaptureBrightness.ok,
      );
    });

    test('reset은 적정 상태로 되돌린다', () {
      final classifier = BrightnessClassifier()..classify(10);
      expect(classifier.current, CaptureBrightness.tooDark);
      classifier.reset();
      expect(classifier.current, CaptureBrightness.ok);
    });
  });
}
