import 'dart:async';

import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/child/data/dto/child_consent_dtos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('상세 보기는 서버 약관 전문(contentHtml)을 시트로 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingConsentScreen(
          onSubmit: (_) async {},
          loadConsentTerms: () async => const [
            ConsentTermDto(
              termId: 1,
              termCode: 'SERVICE_TOS',
              title: '서비스 이용약관',
              required: true,
              version: '1.0',
              contentHtml: '<p>제1조(목적) 이 약관은 도담 서비스를 규정합니다.</p>',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('consent-serviceTerms-detail')));
    await tester.pumpAndSettle();

    expect(find.textContaining('제1조(목적)'), findsOneWidget);
  });

  testWidgets('전문 로더가 없으면 상세 보기는 짧은 요약을 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: OnboardingConsentScreen(onSubmit: (_) async {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('consent-serviceTerms-detail')));
    await tester.pumpAndSettle();

    // 서버 전문이 없으면 하드코딩 요약(_ConsentItem.detail)을 다이얼로그로 보여준다.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('이용 조건과 사용자 권리'), findsOneWidget);
  });
  testWidgets('필수 약관(서비스 이용약관)에 동의해야 완료할 수 있다', (tester) async {
    ConsentAgreementInput? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingConsentScreen(
          onSubmit: (input) async => submitted = input,
        ),
      ),
    );

    // 보호자 가입 단계에는 아동 관련 동의 항목이 없다(S15P11B209-884).
    expect(find.byKey(const ValueKey('consent-childPrivacy')), findsNothing);
    expect(find.byKey(const ValueKey('consent-drawingAnalysis')), findsNothing);
    expect(find.byKey(const ValueKey('consent-voiceProcessing')), findsNothing);
    expect(find.byKey(const ValueKey('consent-serviceTerms')), findsOneWidget);

    final submit = find.byKey(const ValueKey('consent-submit'));
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: submit, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );

    // 서비스 이용약관(유일한 필수)에 동의하면 완료할 수 있다.
    await tester.tap(find.byKey(const ValueKey('consent-serviceTerms')));
    await tester.pump();
    await tester.ensureVisible(submit);
    await tester.tap(
      find.descendant(of: submit, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.isAgreed(ConsentCode.serviceTerms), isTrue);
    expect(submitted!.isAgreed(ConsentCode.childPrivacy), isFalse);
  });

  testWidgets('전체 동의는 모든 필수·선택 항목을 선택하고 해제한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: OnboardingConsentScreen(onSubmit: (_) async {})),
    );

    await tester.tap(find.byKey(const ValueKey('consent-all')));
    await tester.pump();

    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((checkbox) => checkbox.value == true),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('consent-all')));
    await tester.pump();
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((checkbox) => checkbox.value == false),
      isTrue,
    );
  });

  testWidgets('제출 중에는 중복 요청을 막는다', (tester) async {
    final completer = Completer<void>();
    var submitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingConsentScreen(
          onSubmit: (_) {
            submitCount += 1;
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('consent-all')));
    await tester.pump();
    final submit = find.byKey(const ValueKey('consent-submit'));
    await tester.ensureVisible(submit);
    final button = find.descendant(
      of: submit,
      matching: find.byType(FilledButton),
    );
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);

    expect(submitCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('저장 실패 시 다시 시도할 수 있는 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingConsentScreen(
          onSubmit: (_) => Future<void>.error(Exception('failed')),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('consent-all')));
    await tester.pump();
    final submit = find.byKey(const ValueKey('consent-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(
      find.descendant(of: submit, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('consent-submit-error')), findsOneWidget);
  });

  testWidgets('작은 화면에서도 오버플로 없이 표시한다', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: OnboardingConsentScreen(onSubmit: (_) async {})),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
