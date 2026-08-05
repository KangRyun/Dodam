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

  /// 크레용 캔버스 화면 전용 색이다(S15P11B209-797~807). 종이 질감과 크레용 도구
  /// 위에서 대비를 확보하도록 고른 값이라 일반 화면 토큰과 구분해 둔다.
  static const Color canvasPrimary = brandYellow;
  static const Color canvasPrimaryPressed = Color(0xFFE5C84F);
  static const Color canvasInk = Color(0xFF3A3832);
  static const Color canvasWarm = Color(0xFFFFFDF5);

  /// 도구 툴바가 놓이는 면이다. 테두리 원화 안쪽은 비어 있어 이 색을 깔지
  /// 않으면 바깥 배경이 그대로 비친다.
  static const Color canvasToolbarSurface = Color(0xFFFBF5E8);
  static const Color canvasBorder = Color(0xFFE5DFC8);
  static const Color canvasBorderStrong = Color(0xFFC9BF99);

  /// 캔버스 우측 상단 저장 상태 문구 색이다. 저장 단계를 색으로도 구분한다.
  static const Color canvasStatusLocalInk = canvasInk;
  static const Color canvasStatusSavingInk = Color(0xFF655194);
  static const Color canvasStatusSavedInk = Color(0xFF3D7A55);
  static const Color canvasStatusFailedInk = Color(0xFFB33A3A);

  /// 캔버스 팔레트가 제공하는 그리기 색이다.
  ///
  /// 값은 승인 디자인(`prototype/styles.css`)의 swatch 와 같다. 일반 화면이 쓰는
  /// drawingRed·drawingYellow·drawingBlue 와는 톤이 달라 캔버스 전용으로 따로 둔다.
  static const Color canvasSwatchRed = Color(0xFFC74D3F);
  static const Color canvasSwatchOrange = Color(0xFFED741A);
  static const Color canvasSwatchYellow = Color(0xFFEFC63F);
  static const Color canvasSwatchGreen = Color(0xFF6C9E3A);
  static const Color canvasSwatchTeal = Color(0xFF59A7A1);
  static const Color canvasSwatchBlue = Color(0xFF2D77C7);
  static const Color canvasSwatchPurple = Color(0xFF7650AD);
  static const Color canvasSwatchCharcoal = Color(0xFF3A3832);

  /// 스케치북·툴바 테두리를 그리는 크레용 색이다.
  static const Color canvasFrameInk = Color(0xFF67655B);

  /// 스케치북 위쪽 제본 띠 색이다. 스프링이 이 띠를 물고 있다.
  static const Color canvasBindingBand = Color(0xFFF4C64C);

  /// 제본 띠를 감는 스프링 철사 색이다.
  static const Color canvasBindingWire = Color(0xFFFDF8EC);

  /// 캔버스 화면의 바깥 배경과 스케치북이 놓이는 면이다.
  ///
  /// 배경은 앱 포인트 옐로를 옅게 푼 톤이다. 흰 종이와 대비를 두면서도 아이
  /// 화면답게 따뜻하다.
  static const Color canvasBackdrop = Color(0xFFFCEEC4);
  static const Color canvasStage = Color(0xFFF5F1E6);

  static const Color drawingCharcoal = canvasSwatchCharcoal;
  static const Color drawingOrange = canvasSwatchOrange;
  static const Color drawingGreen = canvasSwatchGreen;
  static const Color drawingTeal = canvasSwatchTeal;
  static const Color drawingPurple = canvasSwatchPurple;
}
