import 'dart:typed_data';

/// 촬영 프리뷰 밝기 상태. 촬영을 막지 않고 안내(경고)에만 쓴다.
enum CaptureBrightness { tooDark, ok, tooBright }

/// 0~255 평균 휘도 기준 임계값. 종이 그림 촬영에 맞춰 다소 관대하게 잡는다.
const double kDarkLumaThreshold = 65;
const double kBrightLumaThreshold = 205;

/// 임계 경계에서 안내가 깜빡이지 않도록 하는 히스테리시스 여유값.
const double kBrightnessHysteresis = 14;

/// YUV420 Y(휘도) plane에서 평균 밝기를 추정한다.
///
/// 매 프레임 전체를 훑지 않고 [stride] 간격으로 서브샘플링해 비용을 낮춘다.
/// row padding이 섞여도 밝기 추정에는 무해하므로 bytes 전체를 대상으로 한다.
double averageLumaFromYPlane(Uint8List yPlane, {int stride = 17}) {
  if (yPlane.isEmpty) return 0;
  final step = stride < 1 ? 1 : stride;
  var sum = 0;
  var count = 0;
  for (var i = 0; i < yPlane.length; i += step) {
    sum += yPlane[i];
    count += 1;
  }
  return count == 0 ? 0 : sum / count;
}

/// 평균 휘도를 밝기 상태로 분류한다. 히스테리시스로 경계 떨림을 막는다.
///
/// `ok`에서 벗어나려면 임계값을 넘어야 하고, `ok`로 돌아오려면 임계값에서
/// [kBrightnessHysteresis]만큼 더 안쪽으로 들어와야 한다.
class BrightnessClassifier {
  CaptureBrightness _current = CaptureBrightness.ok;

  CaptureBrightness get current => _current;

  CaptureBrightness classify(double luma) {
    switch (_current) {
      case CaptureBrightness.ok:
        if (luma < kDarkLumaThreshold) {
          _current = CaptureBrightness.tooDark;
        } else if (luma > kBrightLumaThreshold) {
          _current = CaptureBrightness.tooBright;
        }
      case CaptureBrightness.tooDark:
        if (luma > kDarkLumaThreshold + kBrightnessHysteresis) {
          _current = CaptureBrightness.ok;
        }
      case CaptureBrightness.tooBright:
        if (luma < kBrightLumaThreshold - kBrightnessHysteresis) {
          _current = CaptureBrightness.ok;
        }
    }
    return _current;
  }

  void reset() => _current = CaptureBrightness.ok;
}
