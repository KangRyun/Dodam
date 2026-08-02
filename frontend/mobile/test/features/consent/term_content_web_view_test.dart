import 'package:dodam/features/consent/presentation/screens/term_content_web_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 웹뷰 본체(`WebViewController`·`WebViewWidget`)는 플랫폼 구현이 있어야 만들 수
/// 있어 `flutter test`에서 생성할 수 없다. 그래서 화면에서 분리해 둔 순수 판단
/// 함수([allowsTermContentNavigation])와 표시 위젯([TermContentView])을 검증한다.
void main() {
  group('allowsTermContentNavigation', () {
    final initial = Uri.parse('https://example.com/legal/terms');

    test('같은 호스트의 다른 경로·조항 앵커는 앱 안에서 연다', () {
      expect(
        allowsTermContentNavigation(
          initial: initial,
          requestUrl: 'https://example.com/legal/terms#제3조',
        ),
        isTrue,
      );
      expect(
        allowsTermContentNavigation(
          initial: initial,
          requestUrl: 'https://example.com/legal/privacy?v=2',
        ),
        isTrue,
      );
    });

    test('같은 호스트면 http→https 리다이렉트도 연다', () {
      expect(
        allowsTermContentNavigation(
          initial: Uri.parse('http://example.com/terms'),
          requestUrl: 'https://example.com/terms',
        ),
        isTrue,
      );
    });

    test('www 접두사만 다르면 같은 사이트로 본다', () {
      expect(
        allowsTermContentNavigation(
          initial: initial,
          requestUrl: 'https://www.example.com/legal/terms',
        ),
        isTrue,
      );
      expect(
        allowsTermContentNavigation(
          initial: Uri.parse('https://www.example.com/terms'),
          requestUrl: 'https://example.com/terms',
        ),
        isTrue,
      );
    });

    test('다른 호스트로 나가는 이동은 막는다', () {
      expect(
        allowsTermContentNavigation(
          initial: initial,
          requestUrl: 'https://evil.com/login',
        ),
        isFalse,
      );
      // 접미사·접두사가 겹쳐도 다른 사이트다.
      expect(
        allowsTermContentNavigation(
          initial: initial,
          requestUrl: 'https://example.com.evil.com/login',
        ),
        isFalse,
      );
      expect(
        allowsTermContentNavigation(
          initial: initial,
          requestUrl: 'https://notexample.com/login',
        ),
        isFalse,
      );
      expect(
        allowsTermContentNavigation(
          initial: initial,
          requestUrl: 'https://evil.example.com.attacker.io/',
        ),
        isFalse,
      );
    });

    test('호스트가 같아도 http·https가 아닌 스킴은 막는다', () {
      expect(
        allowsTermContentNavigation(
          initial: initial,
          requestUrl: 'ftp://example.com/legal/terms',
        ),
        isFalse,
      );
      expect(
        allowsTermContentNavigation(
          initial: initial,
          requestUrl: 'intent://example.com/#Intent;end',
        ),
        isFalse,
      );
    });

    test('호스트가 없거나 해석할 수 없는 주소는 막는다', () {
      for (final url in [
        'javascript:alert(1)',
        'about:blank',
        'data:text/html,<h1>hi</h1>',
        'mailto:a@example.com',
        '/legal/terms',
        '',
        'http://[',
      ]) {
        expect(
          allowsTermContentNavigation(initial: initial, requestUrl: url),
          isFalse,
          reason: url,
        );
      }
    });
  });

  group('TermContentView', () {
    testWidgets('상단바에 약관 제목을 띄우고 로딩 중에는 오버레이를 덮는다', (tester) async {
      await _pumpView(tester, loading: true, failed: false);

      expect(find.text('서비스 이용약관'), findsOneWidget);
      expect(find.byKey(const ValueKey('term-content-web-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('term-content-loading')), findsOneWidget);
      expect(find.text('약관 전문을 불러오지 못했어요'), findsNothing);
    });

    testWidgets('로딩이 끝나면 오버레이를 걷는다', (tester) async {
      await _pumpView(tester, loading: false, failed: false);

      expect(find.byKey(const ValueKey('term-content-web-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('term-content-loading')), findsNothing);
    });

    testWidgets('실패하면 웹뷰 대신 안내와 다시 시도 버튼을 보여준다', (tester) async {
      var retried = 0;
      await _pumpView(
        tester,
        loading: false,
        failed: true,
        onRetry: () => retried++,
      );

      expect(find.text('약관 전문을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('네트워크 상태를 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byKey(const ValueKey('term-content-web-view')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('term-content-retry')));
      await tester.pump();

      expect(retried, 1);
    });

    testWidgets('오류 화면에서 다시 시도하면 로딩 상태로 되돌아간다', (tester) async {
      var loading = false;
      var failed = true;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => TermContentView(
              title: '서비스 이용약관',
              webView: const SizedBox(key: ValueKey('term-content-web-view')),
              loading: loading,
              failed: failed,
              onRetry: () => setState(() {
                loading = true;
                failed = false;
              }),
            ),
          ),
        ),
      );

      expect(find.text('약관 전문을 불러오지 못했어요'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('term-content-retry')));
      await tester.pump();

      expect(find.text('약관 전문을 불러오지 못했어요'), findsNothing);
      expect(find.byKey(const ValueKey('term-content-web-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('term-content-loading')), findsOneWidget);
    });
  });
}

Future<void> _pumpView(
  WidgetTester tester, {
  required bool loading,
  required bool failed,
  VoidCallback? onRetry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TermContentView(
        title: '서비스 이용약관',
        webView: const SizedBox(key: ValueKey('term-content-web-view')),
        loading: loading,
        failed: failed,
        onRetry: onRetry ?? () {},
      ),
    ),
  );
  // 로딩 표시가 계속 도는 애니메이션이라 pumpAndSettle을 쓰지 않는다.
  await tester.pump();
}
