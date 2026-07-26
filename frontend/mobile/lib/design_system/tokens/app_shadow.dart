import 'package:flutter/material.dart';

/// 그림자(elevation) 디자인 토큰 (S15P11B209-435).
///
/// ⚠️ 골격(skeleton) 단계 — 값은 현행 관측값 placeholder이며, 다음 주 새 디자인
/// 확정 시 이 파일에서 값만 교체한다(참조 컴포넌트는 수정 불필요).
/// 이름은 의미 기반(card·overlay)이라 값이 바뀌어도 뜻이 유지된다.
abstract final class AppShadow {
  /// 카드·패널 — 은은한 그림자. (현행 0x14 / blur 16 / y 6)
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// 오버레이·팝오버 — 살짝 더 또렷. (현행 0x18 / blur 12 / y 4)
  static const List<BoxShadow> overlay = [
    BoxShadow(color: Color(0x18000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// 그림자 없음(플랫). `elevation: 0` 자리 명시용.
  static const List<BoxShadow> none = [];
}
