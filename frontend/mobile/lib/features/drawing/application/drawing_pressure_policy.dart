import 'dart:ui';

/// PointerEvent 필압을 Stroke 계약 값(0..1 또는 null)으로 바꾸는 단일 정책.
///
/// Flutter 계약에서 pressure는 1.0이 "보통"이고 [1.0 초과 ~ pressureMax]가
/// 더 강한 압력이다. Backend 계약은 0..1이므로 초과분은 1.0으로 포화만 하고,
/// `(p-min)/(max-min)` 선형 정규화는 쓰지 않는다 — 기기마다 "보통"의 위치가
/// 달라져 기기 간 비교 의미가 깨진다.
abstract final class DrawingPressurePolicy {
  /// 스타일러스 계열이 아니거나 기기 범위를 신뢰할 수 없으면 null을 돌려준다.
  ///
  /// * touch·mouse 등에는 가짜 필압(항상 1.0)을 만들지 않는다.
  /// * `pressureMin == pressureMax`는 필압 미지원 기기의 보고 형태다.
  /// * 0.0은 "감지 가능한 압력 없음"이라는 유효한 측정값이므로 유지한다.
  static double? resolve({
    required PointerDeviceKind kind,
    required double pressure,
    required double pressureMin,
    required double pressureMax,
  }) {
    final stylus =
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
    if (!stylus) return null;
    // 손상된 값이 그대로 흐르면 jsonEncode가 NaN/Infinity에서 예외를 던진다.
    if (!pressure.isFinite || !pressureMin.isFinite || !pressureMax.isFinite) {
      return null;
    }
    if (pressureMax <= pressureMin) return null;
    // TODO(DEVICE): Verify capability reporting on the target Galaxy Tab/S Pen.
    return pressure.clamp(0.0, 1.0);
  }
}
