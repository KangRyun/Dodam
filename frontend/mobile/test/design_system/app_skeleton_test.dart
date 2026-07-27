import 'package:dodam/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 시머는 repeat() 무한 애니메이션이라 pumpAndSettle은 타임아웃한다 → pump()만 사용한다.
  // 모션 최소화 설정을 검증하려면 MediaQuery를 MaterialApp '안쪽'에서 덮어써야 한다
  // (MaterialApp이 뷰 기준 MediaQuery를 새로 주입하므로, 바깥에 두면 무시됨).
  Widget subject(Widget child, {bool disableAnimations = false}) => MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );

  testWidgets('스켈레톤은 시머와 함께 자리표시자를 렌더한다', (tester) async {
    await tester.pumpWidget(subject(const AppSkeleton(width: 120, height: 16)));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AppSkeleton), findsOneWidget);
    // 애니메이션이 켜진 기본 경로에서는 시머(ShaderMask)가 존재한다
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('모션 최소화 설정이면 시머(ShaderMask)를 끄고 정적으로 표시한다', (tester) async {
    await tester.pumpWidget(
      subject(const AppSkeleton(width: 120, height: 16), disableAnimations: true),
    );
    await tester.pump();

    // 접근성 분기: 애니메이션 대신 정적 자리표시자만 남는다
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.byType(AppSkeleton), findsOneWidget);
  });

  testWidgets('스켈레톤 리스트는 스크린리더에 불러오는 중을 한 번 알린다', (tester) async {
    final handle = tester.ensureSemantics(); // 시맨틱 트리 활성화 필요
    await tester.pumpWidget(subject(const AppSkeletonList(itemCount: 3)));
    await tester.pump(const Duration(milliseconds: 200));

    // 낱개 블록은 시맨틱에서 제외되고 컨테이너 라벨만 노출
    expect(find.bySemanticsLabel('불러오는 중'), findsOneWidget);
    // 3행 × (원형 1 + 라인 2) = 9개 자리표시자
    expect(find.byType(AppSkeleton), findsNWidgets(9));

    handle.dispose();
  });
}
