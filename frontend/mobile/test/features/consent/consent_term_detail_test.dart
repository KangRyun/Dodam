import 'package:dodam/features/child/data/dto/child_consent_dtos.dart';
import 'package:dodam/features/consent/data/dto/consent_status_dtos.dart';
import 'package:dodam/features/consent/domain/repositories/consent_repository.dart';
import 'package:dodam/features/consent/presentation/screens/consent_management_screen.dart';
import 'package:dodam/features/consent/presentation/widgets/consent_term_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('consentTermPlainText', () {
    test('null이면 빈 문자열이다', () {
      expect(consentTermPlainText(null), '');
    });

    test('태그를 걷어내고 br은 줄바꿈, p 끝은 빈 줄로 바꾼다', () {
      const html = '<p>제1조 목적<br>가</p><p>제2조 정의</p>';

      expect(consentTermPlainText(html), '제1조 목적\n가\n\n제2조 정의');
    });

    test('br·p가 아닌 블록 태그는 줄바꿈을 만들지 않는다', () {
      // 문단 구분을 p·br로만 판단하므로 h1 뒤 텍스트는 같은 줄에 이어 붙는다.
      //
      // 알려진 한계를 고정한 단언이지 바람직한 결과가 아니다. 법무 확정 약관
      // 원문에는 h1~h3·li·table이 거의 반드시 들어가는데, 그런 원문이 들어오면
      // 전문이 한 덩어리로 붙어 읽을 수 없게 된다. 원문 시드 시 태그별 줄바꿈
      // 규칙을 넓히고 이 단언도 함께 바꿔야 한다.
      const html = '<h1>서비스 이용약관</h1>제1조 목적';

      expect(consentTermPlainText(html), '서비스 이용약관제1조 목적');
    });

    test('HTML 엔티티를 원래 문자로 되돌린다', () {
      const html = '&lt;주의&gt; A&nbsp;&amp;&nbsp;B &quot;동의&quot;';

      expect(consentTermPlainText(html), '<주의> A & B "동의"');
    });

    test('빈 줄이 3줄 이상이면 두 줄로 줄이고 앞뒤 공백을 없앤다', () {
      const html = '  <p>가</p><p>나</p>  ';

      expect(consentTermPlainText(html), '가\n\n나');
    });

    test('대문자 태그와 속성이 붙은 br도 처리한다', () {
      const html = '<P>가<BR />나</P>';

      expect(consentTermPlainText(html), '가\n나');
    });
  });

  group('consentTermContentUri', () {
    test('http·https 절대 주소만 통과시킨다', () {
      expect(
        consentTermContentUri('https://example.com/legal/terms/'),
        Uri.parse('https://example.com/legal/terms/'),
      );
      expect(
        consentTermContentUri('http://example.com/terms'),
        Uri.parse('http://example.com/terms'),
      );
    });

    test('조항 앵커(fragment)가 붙은 주소도 통과시킨다', () {
      // Uri.isAbsolute는 fragment가 있으면 false라, 그것으로 거르면 조항 앵커를
      // 단 약관 주소가 통째로 막힌다.
      expect(
        consentTermContentUri('https://example.com/terms#제3조'),
        Uri.parse('https://example.com/terms#제3조'),
      );
      expect(
        consentTermContentUri('https://example.com/terms?v=2#s3'),
        Uri.parse('https://example.com/terms?v=2#s3'),
      );
      expect(consentTermContentUri('https://example.com/terms#'), isNotNull);
    });

    test('앞뒤 공백은 다듬는다', () {
      expect(
        consentTermContentUri('  https://example.com/terms  '),
        Uri.parse('https://example.com/terms'),
      );
    });

    test('비어 있거나 null이면 null이다', () {
      expect(consentTermContentUri(null), isNull);
      expect(consentTermContentUri(''), isNull);
      expect(consentTermContentUri('   '), isNull);
    });

    test('상대 경로나 호스트 없는 주소는 거른다', () {
      expect(consentTermContentUri('/legal/terms'), isNull);
      expect(consentTermContentUri('legal/terms'), isNull);
      expect(consentTermContentUri('https:///terms'), isNull);
    });

    test('http·https가 아닌 스킴은 거른다', () {
      expect(consentTermContentUri('javascript:alert(1)'), isNull);
      expect(consentTermContentUri('ftp://example.com/terms'), isNull);
      expect(consentTermContentUri('mailto:a@example.com'), isNull);
    });
  });

  group('약관 상세 시트', () {
    testWidgets('상세 버튼을 누르면 제목·필수여부·버전과 본문이 뜬다', (tester) async {
      await _pumpScreen(
        tester,
        term: const ConsentTermDto(
          termId: 1,
          termCode: 'SERVICE_TOS',
          title: '서비스 이용약관',
          required: true,
          version: 'v1',
          contentHtml: '<p>제1조 목적</p>',
        ),
      );

      await _openDetail(tester, termId: 1);

      expect(find.text('서비스 이용약관'), findsWidgets);
      expect(find.text('필수 · 버전 v1'), findsOneWidget);
      expect(find.text('제1조 목적'), findsOneWidget);
    });

    testWidgets('선택 약관이고 버전이 없으면 "선택"만 보여준다', (tester) async {
      await _pumpScreen(
        tester,
        term: const ConsentTermDto(
          termId: 2,
          termCode: 'MARKETING',
          title: '마케팅 수신',
          required: false,
          version: '',
          contentHtml: '<p>광고성 정보</p>',
        ),
      );

      await _openDetail(tester, termId: 2);

      expect(find.text('선택'), findsWidgets);
      expect(find.textContaining('버전'), findsNothing);
    });

    testWidgets('contentUrl만 있으면 전문 보기 버튼으로 그 주소를 연다', (tester) async {
      final opened = <(String, Uri)>[];
      await _pumpScreen(
        tester,
        term: const ConsentTermDto(
          termId: 3,
          termCode: 'PRIVACY',
          title: '개인정보 처리방침',
          required: true,
          version: 'v2',
          contentUrl: 'https://example.com/legal/privacy/',
        ),
        openTermUrl: (context, title, url) => opened.add((title, url)),
      );

      await _openDetail(tester, termId: 3);

      expect(find.text('약관 전문은 웹 페이지에서 확인할 수 있어요.'), findsOneWidget);
      expect(find.text('약관 상세 내용을 제공하지 않아요.'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('consent-detail-open-url-3')));
      await tester.pumpAndSettle();

      expect(opened, [
        ('개인정보 처리방침', Uri.parse('https://example.com/legal/privacy/')),
      ]);
    });

    testWidgets('contentHtml이 있으면 contentUrl보다 우선해 본문을 보여준다', (tester) async {
      await _pumpScreen(
        tester,
        term: const ConsentTermDto(
          termId: 4,
          termCode: 'SERVICE_TOS',
          title: '서비스 이용약관',
          required: true,
          version: 'v1',
          contentHtml: '<p>본문 우선</p>',
          contentUrl: 'https://example.com/legal/terms/',
        ),
      );

      await _openDetail(tester, termId: 4);

      expect(find.text('본문 우선'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('consent-detail-open-url-4')),
        findsNothing,
      );
    });

    testWidgets('contentUrl 스킴이 http·https가 아니면 링크 없이 안내 문구를 보여준다', (tester) async {
      // host가 있는 주소라야 host 검사를 통과해 스킴 허용목록까지 도달한다.
      // javascript: 처럼 host가 빈 주소를 쓰면 스킴 검사는 실행되지 않는다.
      await _pumpScreen(
        tester,
        term: const ConsentTermDto(
          termId: 5,
          termCode: 'AI_TRAINING',
          title: 'AI 학습 활용',
          required: false,
          version: 'v1',
          contentUrl: 'ftp://example.com/terms',
        ),
      );

      await _openDetail(tester, termId: 5);

      expect(find.text('약관 상세 내용을 제공하지 않아요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('consent-detail-open-url-5')),
        findsNothing,
      );
    });

    testWidgets('contentUrl에 host가 없으면 링크 없이 안내 문구를 보여준다', (tester) async {
      await _pumpScreen(
        tester,
        term: const ConsentTermDto(
          termId: 7,
          termCode: 'AI_TRAINING',
          title: 'AI 학습 활용',
          required: false,
          version: 'v1',
          contentUrl: 'javascript:alert(1)',
        ),
      );

      await _openDetail(tester, termId: 7);

      expect(find.text('약관 상세 내용을 제공하지 않아요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('consent-detail-open-url-7')),
        findsNothing,
      );
    });

    testWidgets('조항 앵커가 붙은 contentUrl도 전문 보기 버튼으로 연다', (tester) async {
      final opened = <(String, Uri)>[];
      await _pumpScreen(
        tester,
        term: const ConsentTermDto(
          termId: 8,
          termCode: 'PRIVACY',
          title: '개인정보 처리방침',
          required: true,
          version: 'v2',
          contentUrl: 'https://example.com/legal/privacy#제3조',
        ),
        openTermUrl: (context, title, url) => opened.add((title, url)),
      );

      await _openDetail(tester, termId: 8);

      expect(find.text('약관 상세 내용을 제공하지 않아요.'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('consent-detail-open-url-8')));
      await tester.pumpAndSettle();

      expect(opened, [
        ('개인정보 처리방침', Uri.parse('https://example.com/legal/privacy#제3조')),
      ]);
    });

    testWidgets('본문도 주소도 없으면 제공하지 않는다고 안내한다', (tester) async {
      await _pumpScreen(
        tester,
        term: const ConsentTermDto(
          termId: 6,
          termCode: 'VOICE_PROCESSING',
          title: '음성 처리',
          required: false,
          version: 'v1',
        ),
      );

      await _openDetail(tester, termId: 6);

      expect(find.text('약관 상세 내용을 제공하지 않아요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('consent-detail-open-url-6')),
        findsNothing,
      );
    });
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required ConsentTermDto term,
  TermUrlOpener? openTermUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ConsentManagementScreen(
        repository: _FakeConsentRepository(userTerms: [term]),
        children: const [],
        openTermUrl: openTermUrl,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDetail(WidgetTester tester, {required int termId}) async {
  await tester.tap(find.byKey(ValueKey('consent-detail-$termId')));
  await tester.pumpAndSettle();
}

final class _FakeConsentRepository implements ConsentRepository {
  _FakeConsentRepository({this.userTerms = const []});

  final List<ConsentTermDto> userTerms;

  @override
  Future<List<ConsentTermDto>> getTerms([ConsentTargetScope? scope]) async =>
      scope == ConsentTargetScope.child ? const [] : userTerms;

  @override
  Future<ConsentStatusDto> getStatus({int? childId}) async => ConsentStatusDto(
    childId: childId,
    requiredConsentsSatisfied: true,
    items: [
      for (final term in userTerms)
        ConsentStatusItemDto(
          termId: term.termId,
          termCode: term.termCode,
          required: term.required,
          version: term.version,
          agreed: true,
        ),
    ],
  );

  @override
  Future<void> changeOptional({
    int? childId,
    required List<ConsentAgreementDto> agreements,
  }) async {}
}
