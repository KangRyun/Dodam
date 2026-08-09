import 'dart:async';

import 'package:dodam/features/child/data/dto/child_consent_dtos.dart';
import 'package:dodam/features/consent/data/dto/consent_status_dtos.dart';
import 'package:dodam/features/consent/domain/repositories/consent_repository.dart';
import 'package:dodam/features/consent/presentation/screens/consent_terms_screen.dart';
import 'package:dodam/features/consent/presentation/widgets/consent_term_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _serviceTos = ConsentTermDto(
  termId: 1,
  termCode: 'SERVICE_TOS',
  title: '서비스 이용약관',
  required: true,
  version: 'v1',
  targetScope: ConsentTargetScope.user,
  contentHtml: '<p>제1조(목적)</p>',
);

const _voice = ConsentTermDto(
  termId: 4,
  termCode: 'VOICE_PROCESSING',
  title: '음성 데이터 처리',
  required: false,
  version: 'v1',
  targetScope: ConsentTargetScope.child,
);

void main() {
  testWidgets('약관을 적용 범위별로 묶어 보여준다', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeConsentRepository(terms: const [_serviceTos, _voice]),
    );

    expect(find.text('약관 및 정책'), findsOneWidget);
    // 섹션 제목은 동의 관리(706)와 공유하는 ConsentSectionCard가 그린다.
    // AppBar 제목과 달리 무엇을 보고 있는지 구분해 주는 헤딩이다.
    expect(find.text('약관'), findsOneWidget);
    expect(find.text('정책 문서'), findsOneWidget);
    expect(find.text('보호자 대상'), findsOneWidget);
    expect(find.text('아동 대상'), findsOneWidget);
    expect(find.text('서비스 이용약관'), findsOneWidget);
    expect(find.text('음성 데이터 처리'), findsOneWidget);
    expect(find.text('버전 v1'), findsNWidgets(2));
  });

  testWidgets('아이를 등록하지 않아도 아동 대상 약관을 읽을 수 있다', (tester) async {
    // 동의 관리 화면은 등록된 아이가 없으면 아동 약관을 아예 띄우지 않는다.
    // 열람 화면은 아동 컨텍스트를 받지 않으므로 그 조건과 무관해야 한다.
    final repository = _FakeConsentRepository(terms: const [_voice]);
    await _pumpScreen(tester, repository: repository);

    expect(find.text('음성 데이터 처리'), findsOneWidget);
    expect(repository.statusCalls, 0);
  });

  testWidgets('읽기 전용이라 동의 토글이 없고 동의를 변경하지 않는다', (tester) async {
    final repository = _FakeConsentRepository(
      terms: const [_serviceTos, _voice],
    );
    await _pumpScreen(tester, repository: repository);

    // 목록이 실제로 그려진 상태에서만 "토글이 없다"가 의미를 가진다.
    expect(find.text('서비스 이용약관'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.byKey(const ValueKey('consent-term-1')));
    await tester.pumpAndSettle();

    expect(repository.changeCalls, 0);
    expect(repository.statusCalls, 0);
  });

  testWidgets('조회가 끝나기 전에는 진행 표시를 보여준다', (tester) async {
    final gate = Completer<List<ConsentTermDto>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ConsentTermsScreen(
          repository: _FakeConsentRepository(gate: gate),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('consent-terms-loading')),
      findsOneWidget,
    );
    expect(find.text('서비스 이용약관'), findsNothing);

    gate.complete(const [_serviceTos]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('consent-terms-loading')), findsNothing);
    expect(find.text('서비스 이용약관'), findsOneWidget);
  });

  testWidgets('약관이 하나도 없으면 빈 목록 안내를 보여준다', (tester) async {
    await _pumpScreen(tester, repository: _FakeConsentRepository());

    expect(find.text('표시할 약관이 없어요.'), findsOneWidget);
    // 정책 문서는 서버 목록과 무관하게 계속 열 수 있어야 한다.
    expect(find.text('개인정보 처리방침'), findsOneWidget);
  });

  testWidgets('조회에 실패하면 안내와 재시도를 보여주고, 다시 시도하면 목록이 뜬다', (tester) async {
    final repository = _FakeConsentRepository(
      terms: const [_serviceTos],
      failure: Exception('boom'),
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('약관 목록을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('서비스 이용약관'), findsNothing);

    repository.failure = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('약관 목록을 불러오지 못했어요'), findsNothing);
    expect(find.text('서비스 이용약관'), findsOneWidget);
  });

  testWidgets('약관을 누르면 상세에 본문이 뜬다', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeConsentRepository(terms: const [_serviceTos]),
    );

    await tester.tap(find.byKey(const ValueKey('consent-term-1')));
    await tester.pumpAndSettle();

    expect(find.text('필수 · 버전 v1'), findsOneWidget);
    expect(find.text('제1조(목적)'), findsOneWidget);
  });

  testWidgets('본문도 주소도 없는 약관은 상세에서 제공하지 않는다고 안내한다', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeConsentRepository(terms: const [_voice]),
    );

    await tester.tap(find.byKey(const ValueKey('consent-term-4')));
    await tester.pumpAndSettle();

    expect(find.text('약관 상세 내용을 제공하지 않아요.'), findsOneWidget);
  });

  testWidgets('개인정보 처리방침을 누르면 공표된 주소를 연다', (tester) async {
    final opened = <(String, Uri)>[];
    await _pumpScreen(
      tester,
      repository: _FakeConsentRepository(terms: const [_serviceTos]),
      openTermUrl: (context, title, url) => opened.add((title, url)),
    );

    await tester.tap(
      find.byKey(const ValueKey('legal-document-개인정보 처리방침')),
    );
    await tester.pumpAndSettle();

    expect(opened, [
      ('개인정보 처리방침', Uri.parse('$kLegalDocumentBaseUrl/privacy/')),
    ]);
  });

  test('정책 문서 주소는 기본 주소 끝의 슬래시와 무관하게 한 겹으로 이어 붙인다', () {
    // dart-define으로 끝에 `/`가 붙은 주소를 주면 `legal//privacy/`가 되어
    // 404 웹뷰가 뜬다. consentTermContentUri는 이를 유효 URI로 통과시킨다.
    expect(
      legalDocumentUrl('privacy/', base: 'https://example.test/legal'),
      'https://example.test/legal/privacy/',
    );
    expect(
      legalDocumentUrl('privacy/', base: 'https://example.test/legal/'),
      'https://example.test/legal/privacy/',
    );
    expect(legalDocumentUrl('privacy/'), '$kLegalDocumentBaseUrl/privacy/');
  });

  test('공표 정책 문서 목록은 서버 약관과 겹치지 않는다', () {
    // 서비스 이용약관은 SERVICE_TOS 약관으로 목록에 이미 나오므로 정적 링크로
    // 한 번 더 넣지 않는다. 같은 문서가 두 줄로 보이면 어느 쪽이 최신인지
    // 사용자가 구분할 수 없다.
    expect(kLegalPolicyDocuments.map((document) => document.title), [
      '개인정보 처리방침',
    ]);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required ConsentRepository repository,
  TermUrlOpener? openTermUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ConsentTermsScreen(
        repository: repository,
        openTermUrl: openTermUrl,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeConsentRepository implements ConsentRepository {
  _FakeConsentRepository({this.terms = const [], this.failure, this.gate});

  final List<ConsentTermDto> terms;
  Object? failure;
  final Completer<List<ConsentTermDto>>? gate;

  int statusCalls = 0;
  int changeCalls = 0;

  @override
  Future<List<ConsentTermDto>> getTerms([ConsentTargetScope? scope]) {
    final pendingGate = gate;
    if (pendingGate != null) return pendingGate.future;
    final pendingFailure = failure;
    if (pendingFailure != null) return Future.error(pendingFailure);
    return Future.value(terms);
  }

  @override
  Future<ConsentStatusDto> getStatus({int? childId}) async {
    statusCalls += 1;
    return const ConsentStatusDto(
      requiredConsentsSatisfied: true,
      items: [],
    );
  }

  @override
  Future<void> changeOptional({
    int? childId,
    required List<ConsentAgreementDto> agreements,
  }) async {
    changeCalls += 1;
  }
}
