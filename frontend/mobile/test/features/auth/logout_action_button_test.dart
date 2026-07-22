import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('로그아웃 취소 시 인증 정보 초기화를 요청하지 않는다', (tester) async {
    var signOutCount = 0;

    await tester.pumpWidget(
      _TestApp(onSignOut: () async => signOutCount += 1, onSignedOut: (_) {}),
    );

    await tester.tap(find.byKey(const ValueKey('logout-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(signOutCount, 0);
  });

  testWidgets('로그아웃 확인 후 인증 정보를 지우고 로그인 이동을 요청한다', (tester) async {
    var signOutCount = 0;
    var navigationCount = 0;

    await tester.pumpWidget(
      _TestApp(
        onSignOut: () async => signOutCount += 1,
        onSignedOut: (_) => navigationCount += 1,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('logout-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃').last);
    await tester.pumpAndSettle();

    expect(signOutCount, 1);
    expect(navigationCount, 1);
  });

  testWidgets('로그아웃 실패 시 현재 화면을 유지하고 오류를 표시한다', (tester) async {
    var navigationCount = 0;

    await tester.pumpWidget(
      _TestApp(
        onSignOut: () async => throw StateError('network'),
        onSignedOut: (_) => navigationCount += 1,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('logout-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃').last);
    await tester.pumpAndSettle();

    expect(navigationCount, 0);
    expect(find.text('로그아웃하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.onSignOut, required this.onSignedOut});

  final AuthSignOut onSignOut;
  final AuthSignedOutNavigation onSignedOut;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(
        actions: [
          LogoutActionButton(onSignOut: onSignOut, onSignedOut: onSignedOut),
        ],
      ),
      body: const Text('보호자 홈'),
    ),
  );
}
