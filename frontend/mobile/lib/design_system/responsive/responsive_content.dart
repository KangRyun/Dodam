import 'package:flutter/widgets.dart';

import '../tokens/app_spacing.dart';

/// 본문을 최대 폭으로 가두고 가운데 정렬하는 래퍼(S15P11B209-787).
///
/// 넓은 태블릿(가로 ~1400dp)에서 텍스트·카드가 화면 끝까지 늘어나 읽기 어려워지는
/// 것을 막는 "Notion식" 장치다. 폭이 [maxWidth]보다 좁으면 아무것도 하지 않고
/// 자식이 폭을 온전히 받는다 — 즉 작은 태블릿에서는 기존 배치와 같다.
///
/// 전체 화면을 균일 스케일하거나 레터박스를 만들지 않는다. 폰트·간격은 절대
/// 크기를 유지하고, 이 위젯은 "가용 폭 상한"만 정한다.
///
/// 세로 제약은 그대로 통과시키므로 자식 안에서 [Expanded]/[Flexible]를 쓰는
/// 배치(예: 2열 그리드, 남은 높이를 채우는 리스트)도 그대로 동작한다.
///
/// 기본 상한은 [AppSizes.wideContentMaxWidth](1120dp)다. 화면별로 더 좁게/넓게
/// 두려면 [maxWidth]를 넘긴다.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    required this.child,
    this.maxWidth = AppSizes.wideContentMaxWidth,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  /// 가둘 대상.
  final Widget child;

  /// 자식이 가질 수 있는 최대 폭(dp). 가용 폭이 이보다 좁으면 무시된다.
  final double maxWidth;

  /// 상한 폭 안쪽에 추가로 줄 여백. 기본은 없음.
  final EdgeInsetsGeometry padding;

  /// 남는 가로 공간 안에서 자식을 어디에 둘지. 기본은 위-가운데.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}
