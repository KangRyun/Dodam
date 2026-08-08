import 'package:dodam/features/report/data/dto/diary_insights_dto.dart';
import 'package:dodam/features/report/data/dto/report_dtos.dart';
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

  testWidgets('가설에는 다른 설명이 함께 보인다', (tester) async {
    // 하나의 해석만 보이면 보호자는 그것을 결론으로 읽는다. 그 한 줄이 가설을 가설로 남긴다.
    await _pump(
      tester,
      _insights(
        observation: const DiarySessionObservationDto(
          title: '성취를 나누고 싶어 한 모습',
          description: '시험 결과를 엄마에게 바로 알렸어요.',
          insightType: 'SESSION_HYPOTHESIS',
          hypothesis: '인정받고 싶은 마음이 있었을 수 있어요.',
          alternativeExplanations: ['기쁨을 함께 나누고 싶었을 수도 있어요.'],
          scopeText: '이번 활동에서 확인된 모습이에요.',
        ),
      ),
    );

    expect(find.text('이번 활동에서 볼 수 있는 것'), findsOneWidget);
    expect(find.textContaining('인정받고 싶은 마음'), findsOneWidget);
    expect(find.textContaining('기쁨을 함께 나누고'), findsOneWidget);
  });

  testWidgets('확인된 표현과 더 볼 것은 다른 라벨로 보인다', (tester) async {
    await _pump(tester, _insights());
    expect(find.text('아이가 들려준 것'), findsOneWidget);

    await _pump(
      tester,
      _insights(
        observation: const DiarySessionObservationDto(
          title: '밤하늘과 누워 있는 인물을 그렸어요',
          description: '슬픔을 골랐지만 음성 설명은 없었어요.',
          insightType: 'EXPLORE_NEXT',
          clarificationQuestion: '이 그림에서 무슨 일이 있었는지 물어볼까요?',
          scopeText: '이번 활동에서 확인된 모습이에요.',
        ),
      ),
    );
    expect(find.text('더 확인해 볼 것'), findsOneWidget);
    expect(find.textContaining('무슨 일이 있었는지'), findsOneWidget);
  });

  testWidgets('확인하지 못한 것을 침묵하지 않고 적는다', (tester) async {
    // 섹션이 없으면 보호자는 '문제가 없었다'로 읽는다.
    await _pump(
      tester,
      _insights(
        unknownItems: const [
          DiaryUnknownItemDto(
            code: 'NO_EMOTION',
            text: '아이가 고르거나 말한 감정이 없어 마음은 이번에 확인하지 않았어요.',
          ),
        ],
      ),
    );

    expect(find.text('이번에는 확인하지 못했어요'), findsOneWidget);
    expect(find.textContaining('마음은 이번에 확인하지 않았어요'), findsOneWidget);
  });

  testWidgets('연령 맥락은 이번 활동 관찰·범위 고지와 함께만 보인다', (tester) async {
    // 셋 중 하나라도 빠지면 규준 설명이나 발달 평가가 된다.
    await _pump(
      tester,
      _insights(
        developmentalObservations: const [
          DiaryDevelopmentalObservationDto(
            domain: 'NARRATIVE_LANGUAGE',
            status: 'OBSERVED_THIS_SESSION',
            ageContext: '이 시기에는 들었거나 만든 이야기를 두 사건 이상으로 이어 말하는 표현이 발달해 가요.',
            observation: '이번 활동에서 아이는 있었던 일과 그다음 행동을 이어서 이야기했어요.',
            scopeText: '이번 활동에서 확인된 표현이며, 전체 발달 수준을 평가한 결과가 아니에요.',
            sourceIds: ['CDC_5Y_MILESTONES'],
          ),
        ],
      ),
    );

    expect(find.text('연령에 비춰 본 이번 활동'), findsOneWidget);
    expect(find.textContaining('두 사건 이상으로 이어 말하는'), findsOneWidget);
    expect(find.textContaining('있었던 일과 그다음 행동을 이어서'), findsOneWidget);
    expect(find.textContaining('전체 발달 수준을 평가한 결과가 아니에요'), findsOneWidget);
    expect(find.text('출처 CDC_5Y_MILESTONES'), findsOneWidget);
  });

  testWidgets('확인하지 않은 도메인을 지연으로 보여 주지 않는다', (tester) async {
    // 무응답·건너뜀은 발달 결함이 아니다. '못함'으로 옮기는 순간 아이 문제가 된다.
    await _pump(
      tester,
      _insights(
        developmentalObservations: const [
          DiaryDevelopmentalObservationDto(
            domain: 'SOCIAL_UNDERSTANDING',
            status: 'NOT_ASSESSED',
            ageContext: '함께 있던 사람의 행동이나 반응을 이야기했는지 이번 활동에서만 살펴봐요.',
            observation: '이번 활동에서는 확인할 만한 이야기가 충분하지 않아 살펴보지 않았어요.',
            scopeText: '이번 활동에서 확인된 표현이며, 전체 발달 수준을 평가한 결과가 아니에요.',
          ),
        ],
      ),
    );

    expect(find.text('이번에는 확인 안 함'), findsOneWidget);
    for (final word in ['지연', '느림', '부족', '못해']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  test('검수 출처가 없는 맥락도 버리지 않는다', () {
    // 나이를 모르거나 그 도메인에 규준이 없으면 서버는 규준을 주장하지 않는 문장을
    //   보낸다 — 출처 없음을 이유로 거르면 감정·자기표현이 통째로 사라진다.
    final parsed = DiaryInsightsDto.fromJson(const {
      'developmentalObservations': [
        {
          'domain': 'EMOTION_EXPRESSION',
          'status': 'PARTIALLY_OBSERVED',
          'ageContext': '감정을 말이나 선택으로 표현했는지 이번 활동에서만 살펴봐요.',
          'observation': '이번 활동에서 아이는 감정을 보기에서 골랐어요.',
          'scopeText': '이번 활동에서 확인된 표현이며, 전체 발달 수준을 평가한 결과가 아니에요.',
          'sourceIds': <String>[],
        },
        {
          'domain': 'SELF_REFLECTION',
          'status': 'NOT_ASSESSED',
          'ageContext': '',
          'observation': '이번 활동에서는 살펴보지 않았어요.',
          'scopeText': '이번 활동에서 확인된 표현이에요.',
        },
      ],
    });

    // 출처가 없어도 남고, 맥락 자체가 빈 항목만 버린다.
    expect(parsed.developmentalObservations, hasLength(1));
    expect(
      parsed.developmentalObservations.single.domain,
      'EMOTION_EXPRESSION',
    );
  });

  testWidgets('아이 답을 질문과 함께 보여 준다', (tester) async {
    // 답만 늘어놓으면 '보기에서 고름'이 무슨 보기였는지 알 수 없다.
    await _pumpWithTranscript(tester);

    expect(find.text('그때 마음이 어땠어?'), findsOneWidget);
    expect(find.text('"기뻐"'), findsOneWidget);
    expect(find.text('보기에서 고름'), findsOneWidget);
    // 발화만 나열하던 예전 섹션은 문답이 있으면 쓰지 않는다.
    expect(find.text('아이가 들려준 말'), findsNothing);
    expect(find.text('아이와 나눈 이야기'), findsOneWidget);
  });

  testWidgets('건너뛴 질문도 무엇을 넘겼는지 보여 준다', (tester) async {
    // "넘긴 질문이 있어요"라는 문장만으로는 무엇을 넘겼는지 알 수 없다.
    await _pumpWithTranscript(tester);

    expect(find.text('블록은 다시 쌓았어?'), findsOneWidget);
    expect(find.text('이 질문은 건너뛰었어요'), findsOneWidget);
  });

  testWidgets('그림에서 보인 것을 서술로 보여 준다', (tester) async {
    // 표지에 그림을 싣고도 이 줄이 없으면 그림과 아이 이야기를 잇는 근거가 없다.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiaryReportV2Body(
              insights: _insights(),
              visionObservations: const ['블록탑이 무너져 있고 두 아이가 마주 보고 있어요.'],
              drawnItems: const ['블록', '사람'],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('그림에서 보인 것'), findsOneWidget);
    expect(find.textContaining('블록탑이 무너져 있고'), findsOneWidget);
    expect(find.text('그린 것 · 블록, 사람'), findsOneWidget);
  });

  testWidgets('그림 서술이 없으면 그 자리를 만들지 않는다', (tester) async {
    await _pump(tester, _insights());

    expect(find.text('그림에서 보인 것'), findsNothing);
  });

  testWidgets('문답이 없는 구 응답에서는 예전처럼 발화만 보여 준다', (tester) async {
    await _pump(tester, _insights());

    expect(find.text('아이가 들려준 말'), findsOneWidget);
    expect(find.text('아이와 나눈 이야기'), findsNothing);
  });

  test('모르는 주장 세기는 가장 약한 쪽으로 읽는다', () {
    expect(diaryInsightTypeLabel('SOMETHING_NEW'), '더 확인해 볼 것');
  });

  test('모르는 코드는 사용자 문구로 지어내지 않는다', () {
    expect(diaryRealityLabel('SOMETHING_NEW'), isNull);
    expect(diaryTimeScopeLabel('SOMETHING_NEW'), isNull);
    expect(diaryStepLabel('SOMETHING_NEW'), '이야기');
    expect(diaryElicitationLabel('SOMETHING_NEW'), '답변');
    expect(diaryDevelopmentDomainLabel('SOMETHING_NEW'), '이번 활동');
    // 모르는 상태도 '못함'이 아니라 '확인 안 함'으로 읽는다.
    expect(diaryDevelopmentStatusLabel('SOMETHING_NEW'), '이번에는 확인 안 함');
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
  DiarySessionObservationDto? observation,
  List<DiaryUnknownItemDto> unknownItems = const [],
  List<DiaryDevelopmentalObservationDto> developmentalObservations = const [],
}) => DiaryInsightsDto(
  unknownItems: unknownItems,
  developmentalObservations: developmentalObservations,
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
  sessionObservations: [
    observation ??
        const DiarySessionObservationDto(
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

/// 문답이 함께 있는 화면을 띄운다.
Future<void> _pumpWithTranscript(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DiaryReportV2Body(
            insights: _insights(),
            qaPairs: const [
              ReportQaPairDto(
                question: '이 그림에서는 무슨 일이 일어나고 있어?',
                answer: '기분이 좋아서 엄마한테 자랑했어',
                state: 'ANSWERED',
                inputType: 'VOICE',
                sttNeedsConfirmation: false,
                isRepresentative: true,
              ),
              ReportQaPairDto(
                question: '그때 마음이 어땠어?',
                answer: '기뻐',
                state: 'ANSWERED',
                inputType: 'TEXT',
                sttNeedsConfirmation: false,
                isRepresentative: false,
              ),
              ReportQaPairDto(
                question: '블록은 다시 쌓았어?',
                answer: null,
                state: 'SKIPPED',
                inputType: 'TEXT',
                sttNeedsConfirmation: false,
                isRepresentative: false,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
