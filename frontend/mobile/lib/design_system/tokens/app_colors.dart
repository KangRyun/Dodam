import 'package:flutter/material.dart';

/// 색상 디자인 토큰 (S15P11B209-433).
///
/// ⚠️ 골격 단계 — 값(hex)은 현행이며 다음 주 새 디자인 확정 시 이 파일에서 값만
/// 교체한다(참조 컴포넌트 수정 불필요). 이름은 의미 기반(leaf=주색상·error 등)이라
/// 값이 바뀌어도 뜻이 유지된다. 상태색(success/warning/error/disabled)과
/// 변형(~Soft 배경용·~Pressed 눌림)을 포함해 공통 UI에서 재사용한다.
abstract final class AppColors {
  static const Color ink = Color(0xFF27313A);
  static const Color inkMuted = Color(0xFF68737D);
  static const Color canvas = Color(0xFFFFFCF5);
  static const Color childCanvas = Color(0xFFFFF6D9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFF6F7F2);
  static const Color outline = Color(0xFFDDE2DC);
  static const Color outlineStrong = Color(0xFFBFC8C0);

  static const Color leaf = Color(0xFF5F9E73);
  static const Color leafPressed = Color(0xFF477D59);
  static const Color leafSoft = Color(0xFFEAF5EC);
  static const Color tangerine = Color(0xFFD98745);
  static const Color tangerinePressed = Color(0xFFB96A2F);
  static const Color tangerineSoft = Color(0xFFFFEBD8);
  static const Color sunshine = Color(0xFFF4CC58);

  /// 아동 화면 메인 브랜드 옐로(S15P11B209-750). CTA·강조에 쓰고, 어두운
  /// ink 텍스트와 조합해 대비를 확보한다.
  static const Color brandYellow = Color(0xFFF2D765);
  static const Color brandYellowPressed = Color(0xFFE0C23D);
  static const Color brandYellowSoft = Color(0xFFFCF4CE);

  static const Color lavender = Color(0xFF8A76C8);
  static const Color lavenderSoft = Color(0xFFF0ECFF);

  static const Color drawingInk = Color(0xFF30343B);
  static const Color drawingRed = Color(0xFFE35D6A);
  static const Color drawingBlue = Color(0xFF4D82D8);
  static const Color drawingYellow = Color(0xFFF2C94C);

  static const Color success = Color(0xFF4F8C63);
  static const Color successSoft = Color(0xFFE7F4EA);
  static const Color warning = Color(0xFFC7812F);
  static const Color warningSoft = Color(0xFFFFF0D8);
  static const Color error = Color(0xFFB8564F);
  static const Color errorSoft = Color(0xFFFBE9E7);
  static const Color disabled = Color(0xFFD9DDD8);
  static const Color onDisabled = Color(0xFF909892);
}
