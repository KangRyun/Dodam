import 'package:flutter/material.dart';

/// 보호자 홈(태블릿 대시보드) 전용 팔레트·치수. 시안(목업)의 CSS 변수를 그대로
/// 옮겨 색·크기·위치를 1:1로 맞춘다. 앱 공통 토큰(AppColors)과 별개로,
/// 이 화면 고유의 따뜻한 크림+옐로우 톤을 위해 둔다.
abstract final class DodamHome {
  static const page = Color(0xFFECE4D2);
  static const surface = Color(0xFFFFFFFF);
  static const warm = Color(0xFFFBF6EA);
  static const warm2 = Color(0xFFFCF3D8);
  static const point = Color(0xFFF2D765);
  static const pointDeep = Color(0xFFDDB62E);
  static const pointSoft = Color(0xFFFBF1C6);
  static const ink = Color(0xFF332F26);
  static const inkSoft = Color(0xFF8F8878);
  static const inkFaint = Color(0xFFB4AC99);
  static const line = Color(0xFFECE4D2);
  static const green = Color(0xFF5E9A6E);
  static const greenSoft = Color(0xFFE6F1E6);

  /// 알림(소식함) 배너에서 쓰는 차분한 세이지 톤. 활동 카드 배경으로 재사용.
  static const sage = Color(0xFFDDEAD5);
  static const sageSoft = Color(0xFFEEF5E9);
  static const forest = Color(0xFF315B49);

  /// 메인 CTA 버튼 전용 선명한 초록(참고 이미지 기준). hover 시 한 톤 진하게.
  static const ctaGreen = Color(0xFF64A079);
  static const ctaGreenDeep = Color(0xFF548A66);
  static const blue = Color(0xFF4E82CE);
  static const blueSoft = Color(0xFFE7EFFB);
  static const coral = Color(0xFFDE7160);
  static const coralSoft = Color(0xFFFAE8E4);

  static const heroTop = Color(0xFFFFFDF5);
  static const heroBottom = Color(0xFFFCF0CE);
  static const heroBorder = Color(0xFFF0E4B6);
  static const emptyCell = Color(0xFFEEE9DC);
  static const chipBorder = Color(0xFFEFE6CE);

  /// point 배경 위 텍스트(CTA·선택 월).
  static const onPoint = Color(0xFF5C4A10);

  /// 선택된 nav·기분 pill 텍스트.
  static const navOn = Color(0xFF7A6414);
  static const moodDot = Color(0xFF8FC79B);

  /// card 그림자: 0 10px 30px -18px rgba(90,66,20,.5)
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x805A4214),
      offset: Offset(0, 10),
      blurRadius: 30,
      spreadRadius: -18,
    ),
  ];
}
