import 'package:dodam/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const labels = {
    SocialLoginProvider.kakao: '카카오로 시작하기',
    SocialLoginProvider.google: 'Google로 시작하기',
    SocialLoginProvider.naver: '네이버로 시작하기',
  };

  testWidgets('세 소셜 버튼은 동일한 SVG 영역·로고 좌측·라벨 중앙 정렬을 사용한다', (
    tester,
  ) async {
    for (final provider in SocialLoginProvider.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: SocialLoginButton(provider: provider, onPressed: () {}),
              ),
            ),
          ),
        ),
      );

      final button = find.byKey(ValueKey('social-login-${provider.name}'));
      final icon = find.byKey(ValueKey('social-login-${provider.name}-icon'));
      final label = find.text(labels[provider]!);

      // SVG 로고는 3버튼 모두 동일한 20x20 영역을 사용한다.
      expect(
        find.descendant(of: icon, matching: find.byType(SvgPicture)),
        findsOneWidget,
      );
      expect(tester.getSize(icon), const Size.square(20));

      // 라벨은 버튼 전체 기준 가운데 정렬, 16px.
      final text = tester.widget<Text>(label);
      expect(text.textAlign, TextAlign.center);
      expect(text.style?.fontSize, 16);

      // 로고는 버튼 중앙보다 왼쪽에 고정된다.
      final buttonCenterX = tester.getCenter(button).dx;
      expect(tester.getTopRight(icon).dx, lessThan(buttonCenterX));
    }
  });
}
