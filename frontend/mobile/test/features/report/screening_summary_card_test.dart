import 'package:dodam/features/report/data/dto/screening_summary_dto.dart';
import 'package:dodam/features/report/presentation/widgets/screening_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 검사 기록 카드.
///
/// 이 화면이 지켜야 하는 것은 하나다 — **앱이 검사를 해 줬다고 읽히지 않는 것.**
/// 그래서 출처 표시·필수 고지·빈 상태 문구를 화면에서 확인한다.
void main() {
  testWidgets('보호자가 입력한 기록임을 결과보다 먼저 보여 준다', (tester) async {
    // 결과 문구를 먼저 읽으면 뒤에 붙는 단서는 잘 안 읽힌다.
    await _pump(tester, _summary());

    expect(find.text('보호자가 입력한 기록'), findsOneWidget);
    expect(find.text('확인된 공식 결과'), findsNothing);
    expect(find.textContaining('심화평가권고'), findsWidgets);
  });

  testWidgets('선별은 진단이 아니라는 고지가 결과와 함께 나온다', (tester) async {
    await _pump(tester, _summary());

    expect(find.textContaining('진단은 아닙니다'), findsOneWidget);
  });

  testWidgets('기록이 없어도 제공하지 않는다는 사실을 적는다', (tester) async {
    // 침묵하면 보호자는 앱이 선별을 해 준다고 오해한다.
    await _pump(
      tester,
      const ScreeningSummaryDto(
        message: '이 앱은 표준화 선별검사를 제공하지 않아요. 그림일기 기록은 검사 결과가 아니에요.',
      ),
    );

    expect(find.text('검사 기록'), findsOneWidget);
    expect(find.textContaining('표준화 선별검사를 제공하지 않아요'), findsOneWidget);
  });

  testWidgets('영역별 결과와 후속 경로를 함께 보여 준다', (tester) async {
    await _pump(tester, _summary());

    expect(find.textContaining('언어 · 심화평가권고'), findsOneWidget);
    expect(find.textContaining('소아청소년과'), findsOneWidget);
  });

  test('검증되지 않은 기록을 공식 결과로 부르지 않는다', () {
    expect(screeningSourceLabel(false), '보호자가 입력한 기록');
    expect(screeningSourceLabel(true), '확인된 공식 결과');
  });

  test('서버가 안 준 필드는 안전한 기본값으로 읽는다', () {
    // sourceVerified 가 없다고 검증된 것으로 읽으면 미검증 기록이 공식 결과가 된다.
    final parsed = ScreeningRecordDto.fromJson(const {
      'recordId': 1,
      'officialResultText': '결과',
    });

    expect(parsed.sourceVerified, isFalse);
    expect(parsed.sourceAuthorityType, 'GUARDIAN_REPORTED');
  });
}

Future<void> _pump(WidgetTester tester, ScreeningSummaryDto summary) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScreeningSummaryCard(summary: summary),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScreeningSummaryDto _summary() => ScreeningSummaryDto(
  state: 'EXTERNAL_RESULT_AVAILABLE',
  message: '보호자가 직접 입력한 검사 기록이에요. 앱이 확인하거나 채점한 결과가 아니에요.',
  records: [
    ScreeningRecordDto(
      recordId: 1,
      instrumentId: 'K_DST',
      instrumentDisplayName: '한국 영유아 발달선별검사 K-DST',
      completedAt: DateTime(2026, 7, 1),
      sourceAuthorityName: '영유아건강검진',
      officialResultText: '심화평가권고',
      requiredDisclosure: '공식 발달선별 결과이며 진단은 아닙니다. 결과에 따라 정밀평가가 필요할 수 있습니다.',
      domainResults: const [
        ScreeningDomainResultDto(domainName: '언어', resultLabel: '심화평가권고'),
      ],
      referralOptions: const ['소아청소년과', '발달클리닉'],
    ),
  ],
);
