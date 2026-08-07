import 'package:dodam/features/report/data/dto/diary_insights_dto.dart';
import 'package:dodam/features/report/presentation/widgets/diary_report_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 그림일기 리포트 V2 본문.
///
/// 이 화면이 지켜야 하는 것은 한 가지다 — **한 번의 활동을 아이의 지속적인 성향으로
/// 보여 주지 않는 것.** 그래서 범위 문구·질문 방식·실제/상상 표시를 화면에서 확인한다.
void main() {
  testWidgets('아이 이야기를 흐름과 발화로 보여 준다', (tester) async {
    await _pump(tester, _insights());

    expect(find.text('수학시험에서 100점을 받은 날'), findsOneWidget);
    expect(find.text('이야기 흐름'), findsOneWidget);
    expect(find.text('있었던 일'), findsOneWidget);
    expect(find.text('함께 있던 사람의 반응'), findsOneWidget);
    expect(find.text('"기분이 좋아서 엄마한테 자랑했어"'), findsOneWidget);
  });

  testWidgets('이번 활동 관찰에는 범위 문구가 함께 보인다', (tester) async {
    // 범위 문구가 빠지면 한 회차 관찰이 "이 아이는 원래 그렇다"로 읽힌다.
    await _pump(tester, _insights());

    expect(find.text('이번 활동에서 확인된 표현'), findsOneWidget);
    expect(find.text('이번 활동에서 확인된 모습이에요.'), findsOneWidget);
  });

  testWidgets('경향 카드 제목을 쓰지 않는다', (tester) async {
    await _pump(tester, _insights());

    expect(find.text('주요 심리 경향'), findsNothing);
  });

  testWidgets('고른 답과 스스로 한 말을 구분해 보여 준다', (tester) async {
    // 두 답을 같은 근거로 보여 주면 AI 가 제시한 답이 아이의 표현이 된다.
    await _pump(tester, _insights());

    expect(find.text('스스로 이야기함'), findsOneWidget);
    expect(find.text('보기에서 고름'), findsOneWidget);
  });

  testWidgets('아이가 말하지 않은 실제·시점은 표시하지 않는다', (tester) async {
    await _pump(
      tester,
      _insights(realityStatus: 'UNKNOWN', timeScope: 'UNKNOWN'),
    );

    for (final label in const [
      '실제로 있었던 일',
      '상상한 이야기',
      '오늘 있었던 일',
      '어제 있었던 일',
    ]) {
      expect(find.text(label), findsNothing, reason: '$label 을 화면이 정하면 안 된다');
    }
  });

  testWidgets('상상한 이야기는 상상으로 표시한다', (tester) async {
    await _pump(tester, _insights(realityStatus: 'IMAGINED'));

    expect(find.text('상상한 이야기'), findsOneWidget);
    expect(find.text('실제로 있었던 일'), findsNothing);
  });

  testWidgets('내용이 없는 섹션은 그리지 않는다', (tester) async {
    await _pump(
      tester,
      const DiaryInsightsDto(
        storySnapshot: DiaryStorySnapshotDto(headline: '오늘 이야기'),
      ),
    );

    expect(find.text('오늘 이야기'), findsOneWidget);
    expect(find.text('이야기 흐름'), findsNothing);
    expect(find.text('아이가 들려준 말'), findsNothing);
    expect(find.text('이어서 물어보면 좋아요'), findsNothing);
  });

  test('보여 줄 것이 하나도 없으면 V2 를 열지 않는다', () {
    // 듣기 안내 한 줄만으로 화면을 열면 아이 이야기가 없는 리포트가 된다.
    const tipOnly = DiaryInsightsDto(listeningTip: '아이 말을 끝까지 들어주세요.');

    expect(tipOnly.hasContent, isFalse);
  });

  test('아이 발화만으로는 V2 를 열지 않는다', () {
    // childVoiceItems 는 서버가 문답에서 그대로 파생한다 — 문답이 있으면 언제나 채워지므로
    //   이것까지 세면 빈 V2 방지 장치가 늘 참이 되어 무력해진다.
    const voicesOnly = DiaryInsightsDto(
      childVoiceItems: [
        DiaryChildVoiceDto(text: '응', elicitationType: 'YES_NO'),
      ],
    );

    expect(voicesOnly.hasContent, isFalse);
  });

  test('모르는 코드는 사용자 문구로 지어내지 않는다', () {
    expect(diaryRealityLabel('SOMETHING_NEW'), isNull);
    expect(diaryTimeScopeLabel('SOMETHING_NEW'), isNull);
    expect(diaryStepLabel('SOMETHING_NEW'), '이야기');
    expect(diaryElicitationLabel('SOMETHING_NEW'), '답변');
  });
}

Future<void> _pump(WidgetTester tester, DiaryInsightsDto insights) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DiaryReportV2Body(insights: insights),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DiaryInsightsDto _insights({
  String realityStatus = 'REAL',
  String timeScope = 'TODAY',
}) => DiaryInsightsDto(
  storySnapshot: DiaryStorySnapshotDto(
    headline: '수학시험에서 100점을 받은 날',
    summary: '시험에서 100점을 받고 엄마에게 자랑했어요.',
    realityStatus: realityStatus,
    timeScope: timeScope,
    evidenceRefs: const [DiaryEvidenceRefDto(kind: 'QA_ANSWER', id: '101')],
  ),
  narrativeFlow: const [
    DiaryNarrativeStepDto(stepType: 'EVENT', text: '수학시험에서 100점을 받음'),
    DiaryNarrativeStepDto(stepType: 'CHILD_ACTION', text: '엄마에게 자랑함'),
    DiaryNarrativeStepDto(
      stepType: 'OTHER_RESPONSE',
      text: '엄마가 칭찬하고 장난감을 약속함',
    ),
  ],
  childVoiceItems: const [
    DiaryChildVoiceDto(
      text: '기분이 좋아서 엄마한테 자랑했어',
      elicitationType: 'OPEN_INVITATION',
    ),
    DiaryChildVoiceDto(text: '기뻐', elicitationType: 'MULTIPLE_CHOICE'),
  ],
  sessionObservations: const [
    DiarySessionObservationDto(
      title: '성취한 경험과 그때의 마음을 함께 이야기했어요',
      description: '시험 결과와 엄마에게 자랑한 행동을 이어서 설명했어요.',
      scopeText: '이번 활동에서 확인된 모습이에요.',
    ),
  ],
  caregiverQuestions: const [
    DiaryCaregiverQuestionDto(
      question: '엄마한테 자랑했을 때 엄마가 뭐라고 했어?',
      purpose: '그 장면을 더 들어볼 수 있어요.',
    ),
  ],
  listeningTip: '아이가 고른 장난감 이야기를 먼저 들어주세요.',
);
