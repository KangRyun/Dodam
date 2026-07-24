import 'package:dodam/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const labels = {
    SocialLoginProvider.kakao: '카카오로 시작',
    SocialLoginProvider.google: 'Google 계정으로 시작',
    SocialLoginProvider.naver: '네이버로 시작',
  };

  testWidgets('세 소셜 버튼은 동일한 SVG 영역과 레이블 간격을 사용한다', (tester) async {
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

      final icon = find.byKey(ValueKey('social-login-${provider.name}-icon'));
      final label = find.text(labels[provider]!);

      expect(
        find.descendant(of: icon, matching: find.byType(SvgPicture)),
        findsOneWidget,
      );
      expect(tester.getSize(icon), const Size.square(20));
      expect(
        tester.getTopLeft(label).dx - tester.getTopRight(icon).dx,
        closeTo(10, 0.01),
      );
      expect(tester.widget<Text>(label).style?.fontSize, 16);
    }
  });
}
