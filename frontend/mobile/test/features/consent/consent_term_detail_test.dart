import 'package:dodam/features/child/data/dto/child_consent_dtos.dart';
import 'package:dodam/features/consent/data/dto/consent_status_dtos.dart';
import 'package:dodam/features/consent/domain/repositories/consent_repository.dart';
import 'package:dodam/features/consent/presentation/screens/consent_management_screen.dart';
import 'package:dodam/features/consent/presentation/widgets/consent_term_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `consentTermPlainText`가 줄바꿈으로 바꿔야 하는 블록 레벨 태그 전부.
/// 구현의 `_blockLevelTagPattern` 목록과 짝을 이룬다. `li`는 처리가 달라 뺐다.
const _blockLevelTags = <String>[
  'p', 'div', 'section', 'article', 'header', 'footer', 'blockquote', 'hr',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'ul', 'ol', 'dl', 'dt', 'dd',
  'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th',
];

/// 블록 태그와 앞글자가 겹치지만 줄을 바꾸면 안 되는 태그들.
/// `pre`·`param`·`picture`·`progress`·`path`·`polygon`·`pattern`은 `p`와,
/// `track`은 `tr`과 겹쳐 룩어헤드가 없으면 실제로 잘못 잡힌다. 나머지는 대안
/// 나열 순서로 이미 걸러지지만 목록을 손댈 때를 대비해 함께 고정한다.
const _prefixCollidingTags = <String>[
  'pre', 'param', 'picture', 'progress', 'path', 'polygon', 'pattern',
  'track', 'text', 'textarea', 'template', 'time', 'title',
  'html', 'head', 'hgroup',
  'data', 'details', 'dialog', 'option',
];

void main() {
  group('consentTermPlainText', () {
    test('null이면 빈 문자열이다', () {
      expect(consentTermPlainText(null), '');
    });

    test('태그를 걷어내고 br은 줄바꿈, p 끝은 빈 줄로 바꾼다', () {
      const html = '<p>제1조 목적<br>가</p><p>제2조 정의</p>';

      expect(consentTermPlainText(html), '제1조 목적\n가\n\n제2조 정의');
    });

    test('제목 태그 뒤에서 줄을 바꾼다', () {
      const html = '<h1>서비스 이용약관</h1>제1조 목적';

      expect(consentTermPlainText(html), '서비스 이용약관\n제1조 목적');
    });

    test('제목과 문단이 이어지면 빈 줄로 나눈다', () {
      const html = '<h1>서비스 이용약관</h1><h2>제1장 총칙</h2><p>제1조 목적</p>';

      expect(
        consentTermPlainText(html),
        '서비스 이용약관\n\n제1장 총칙\n\n제1조 목적',
      );
    });

    test('목록 항목마다 불릿을 붙여 한 줄씩 나눈다', () {
      const html = '<p>수집 항목</p><ul><li>이름</li><li>생년월일</li></ul>';

      expect(consentTermPlainText(html), '수집 항목\n\n• 이름\n• 생년월일');
    });

    test('목록을 여러 줄로 쓴 원문도 항목 사이에 빈 줄을 넣지 않는다', () {
      // V29 시드처럼 태그를 줄마다 나눠 쓴 원문. </li> 뒤 개행을 함께 먹지 않으면
      // <li>가 만드는 줄바꿈과 겹쳐 항목마다 빈 줄이 생긴다.
      const html =
          '<p>수집 항목</p>\n<ul>\n<li>이름</li>\n<li>생년월일</li>\n</ul>';

      expect(consentTermPlainText(html), '수집 항목\n\n• 이름\n• 생년월일');
    });

    test('번호 목록도 같은 불릿으로 나눈다', () {
      // ol의 순번은 상태를 들고 세어야 나오므로 순수 문자열 변환에서는 재현하지
      // 않는다. 항목이 붙어버리지 않는 것까지만 보장한다.
      const html = '<ol><li>가</li><li>나</li></ol>';

      expect(consentTermPlainText(html), '• 가\n• 나');
    });

    test('div로 나뉜 덩어리를 빈 줄로 나눈다', () {
      const html = '<div>가</div><div>나</div>';

      expect(consentTermPlainText(html), '가\n\n나');
    });

    test('표의 칸이 서로 붙지 않는다', () {
      const html =
          '<table><tr><td>항목</td><td>보관 기간</td></tr>'
          '<tr><td>이름</td><td>1년</td></tr></table>';

      expect(consentTermPlainText(html), '항목\n\n보관 기간\n\n이름\n\n1년');
    });

    test('구분선이 맨 텍스트 사이에서도 줄을 나눈다', () {
      // <p>가</p><hr><p>나</p> 로 쓰면 </p><p> 경계가 이미 빈 줄을 만들어 <hr> 을
      // 목록에서 빼도 결과가 같다. hr 자체를 판별하려면 맨 텍스트 사이에 끼워야 한다.
      expect(consentTermPlainText('가<hr>나'), '가\n나');
      expect(consentTermPlainText('가<hr/>나'), '가\n나');
    });

    test('목록 항목 안의 인라인 태그는 항목을 쪼개지 않는다', () {
      const html = '<ul><li><b>강조</b> 항목</li><li>보통 항목</li></ul>';

      expect(consentTermPlainText(html), '• 강조 항목\n• 보통 항목');
    });

    test('인라인 태그는 줄바꿈을 만들지 않는다', () {
      // 블록 태그를 줄바꿈으로 바꾸면서 인라인까지 함께 바꾸면 강조가 들어간
      // 문장이 중간에서 쪼개진다. 과잉 치환 회귀를 막는 단언이다.
      const html =
          '<p><strong>중요</strong>한 <em>사항</em>을 <span>확인</span>하고 '
          '<a href="https://example.com">약관</a>에 <b>동의</b><i>합니다</i></p>';

      expect(consentTermPlainText(html), '중요한 사항을 확인하고 약관에 동의합니다');
    });

    test('p 여는 태그만 있거나 닫는 태그만 있어도 줄을 바꾼다', () {
      expect(consentTermPlainText('제0조<p>제1조</p>제2조'), '제0조\n제1조\n제2조');
      expect(consentTermPlainText('<p>가<p>나'), '가\n나');
    });

    test('블록 태그가 겹겹이 중첩돼도 빈 줄은 하나까지만 생긴다', () {
      const html =
          '<div><section><h1>제목</h1></section></div><div><p>본문</p></div>';

      final text = consentTermPlainText(html);

      expect(text, '제목\n\n본문');
      expect(text, isNot(contains('\n\n\n')));
    });

    test('블록 태그와 엔티티가 섞여도 순서대로 처리한다', () {
      const html = '<h1>제1조 &lt;목적&gt;</h1><ul><li>A&nbsp;&amp;&nbsp;B</li></ul>';

      expect(consentTermPlainText(html), '제1조 <목적>\n\n• A & B');
    });

    test('이스케이프된 태그 텍스트는 태그로 오인하지 않는다', () {
      // 엔티티 되돌리기가 태그 제거보다 먼저 오면 &lt;p&gt;가 실제 <p>로 되살아나
      // 본문에서 사라진다. 순서를 고정하는 단언이다.
      const html = '<p>&lt;p&gt; 태그는 문단을 뜻해요</p>';

      expect(consentTermPlainText(html), '<p> 태그는 문단을 뜻해요');
    });

    test('대문자 블록 태그와 속성이 붙은 태그도 처리한다', () {
      const html = '<DIV CLASS="a">가</DIV><UL><LI>나</LI></UL>';

      expect(consentTermPlainText(html), '가\n\n• 나');
    });

    test('블록 레벨 태그 목록의 각 태그가 저마다 줄을 바꾼다', () {
      // 목록에서 태그를 지우거나 이름에 오타를 내면 여기서 바로 잡힌다. 이웃한
      // 블록 태그가 결과를 가리지 않도록 맨 텍스트 사이에 하나씩만 끼워 확인한다.
      // 예를 들어 <table><tr><td>로 확인하면 td가 만든 줄바꿈이 table·tr의 부재를
      // 덮어버려 그 둘을 지워도 통과한다.
      for (final tag in _blockLevelTags) {
        expect(
          consentTermPlainText('앞<$tag>뒤'),
          '앞\n뒤',
          reason: '여는 태그 <$tag>가 줄을 바꾸지 않는다',
        );
        expect(
          consentTermPlainText('앞</$tag>뒤'),
          '앞\n뒤',
          reason: '닫는 태그 </$tag>가 줄을 바꾸지 않는다',
        );
      }
    });

    test('목록 항목은 여는 쪽이 불릿을, 닫는 쪽이 줄바꿈을 맡는다', () {
      // li는 블록 태그와 처리가 다르다. 여는 태그는 줄을 바꾸지 않고 불릿만 붙이며,
      // 항목의 줄바꿈은 닫는 태그가 만든다. 첫 항목의 줄바꿈은 앞선 ul·ol이 만든다.
      expect(consentTermPlainText('앞<li>뒤'), '앞• 뒤');
      expect(consentTermPlainText('앞</li>뒤'), '앞\n뒤');
    });

    test('블록 태그와 접두사가 겹치는 태그는 줄을 바꾸지 않는다', () {
      // 정규식의 (?=[\s/>]) 룩어헤드를 지우면 <pre>가 p로, <track>이 tr로 잡혀
      // 문장 중간에서 줄이 끊긴다. 그 안전장치를 고정하는 단언이다.
      for (final tag in _prefixCollidingTags) {
        expect(
          consentTermPlainText('앞<$tag>뒤</$tag>끝'),
          '앞뒤끝',
          reason: '<$tag>가 블록 태그로 잘못 잡혀 줄이 끊긴다',
        );
      }
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
