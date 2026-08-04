import 'package:flutter/widgets.dart';

/// 창 폭 구간(S15P11B209-787).
///
/// Material 3 window size class를 태블릿 가로 사용에 맞춰 단순화했다. 앱은
/// 가로 고정(S15P11B209-864)이라 실사용 폭은 대략 600~1400dp 범위다.
///
/// | 구간         | 폭(dp)      | 태블릿에서의 의미                       |
/// |--------------|-------------|----------------------------------------|
/// | [compact]    | < 600       | 폰/작은 창(참고용) — 태블릿엔 거의 없음 |
/// | [medium]     | 600 ~ 839   | 작은 태블릿·분할 화면                   |
/// | [expanded]   | 840 ~ 1199  | 일반 태블릿 가로                        |
/// | [large]      | >= 1200     | 큰 태블릿 가로                          |
///
/// 폰트·간격 토큰의 절대 크기는 구간과 무관하게 유지한다. 구간은 "무엇을 몇 열로
/// 배치할지"와 "본문을 어디서 최대 폭으로 가둘지"를 정하는 데만 쓴다(전체 화면
/// 스케일 금지).
enum WindowWidthClass {
  compact,
  medium,
  expanded,
  large;

  /// [medium] 하한. 이 미만은 [compact].
  static const double mediumMin = 600;

  /// [expanded] 하한. 태블릿 가로의 기본 구간 시작점.
  static const double expandedMin = 840;

  /// [large] 하한. 큰 태블릿.
  static const double largeMin = 1200;

  /// 논리 폭(dp)으로 구간을 판정한다.
  static WindowWidthClass fromWidth(double width) {
    if (width >= largeMin) return WindowWidthClass.large;
    if (width >= expandedMin) return WindowWidthClass.expanded;
    if (width >= mediumMin) return WindowWidthClass.medium;
    return WindowWidthClass.compact;
  }

  /// 폰/작은 창 구간인지.
  bool get isCompact => this == WindowWidthClass.compact;

  /// 2열·와이드 배치를 쓸 수 있는 넉넉한 구간인지([expanded] 이상).
  bool get isExpandedOrWider =>
      this == WindowWidthClass.expanded || this == WindowWidthClass.large;
}

/// [BuildContext]에서 현재 창 폭 구간을 얻는 편의 확장.
extension WindowWidthClassContext on BuildContext {
  /// 현재 [MediaQuery] 폭으로 판정한 구간.
  WindowWidthClass get widthClass =>
      WindowWidthClass.fromWidth(MediaQuery.sizeOf(this).width);
}
