import 'package:dodam/features/report/data/dto/diary_insights_dto.dart';
import 'package:dodam/features/report/presentation/widgets/diary_report_v3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiaryInsightsDto V3', () {
    test('자료 범위와 전체 음성 대화를 파싱한다', () {
      final dto = DiaryInsightsDto.fromJson(_v3Fixture());

      expect(dto.schemaVersion, 3);
      expect(dto.dataScope?.evidenceLevel, 'RICH');
      expect(dto.storyComponents, hasLength(2));
      expect(dto.drawingObservations.single.childConfirmed, isTrue);
      expect(dto.transcript.single.audioAvailable, isTrue);
      expect(
        dto.transcript.single.audioUrl,
        '/api/v1/conversation-messages/22/audio',
      );
    });

    test('V3 필드가 없는 응답은 V2 기본값으로 읽는다', () {
      final dto = DiaryInsightsDto.fromJson(const {});

      expect(dto.schemaVersion, 2);
      expect(dto.dataScope, isNull);
      expect(dto.storyComponents, isEmpty);
      expect(dto.drawingObservations, isEmpty);
      expect(dto.transcript, isEmpty);
    });
  });

  group('DiaryReportV3Body', () {
    testWidgets('LIMITED 리포트는 자료 범위와 미확인 내용을 표시하고 가설을 숨긴다', (tester) async {
      await _pump(tester, _limitedInsights());

      expect(find.text('이번 기록의 자료 범위'), findsOneWidget);
      expect(find.text('이번에는 확인하지 못했어요'), findsOneWidget);
      expect(find.text('그림과 대화에서 생각해 볼 수 있는 가능성'), findsNothing);
      expect(find.text('아이의 마음이 불편했을 수 있어요.'), findsNothing);
    });

    testWidgets('확인된 그림·이야기와 전체 대화를 근거 순서로 표시한다', (tester) async {
      await _pump(tester, DiaryInsightsDto.fromJson(_v3Fixture()));

      expect(find.text('그림에서 확인된 표현'), findsOneWidget);
      expect(find.text('두 사람이 나란히 있어요.'), findsOneWidget);
      expect(find.text('이야기 구성 지도'), findsOneWidget);
      expect(find.text('친구와 공원에서 놀았어요.'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('전체 대화와 활동 상세'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('전체 대화와 활동 상세'));
      await tester.pumpAndSettle();

      expect(find.textContaining('누구와 함께 있었어?'), findsOneWidget);
      expect(find.text('친구와 있었어요.'), findsOneWidget);
      expect(find.text('음성으로 답함'), findsOneWidget);
    });

    testWidgets('RICH 가설은 다른 설명과 다음 확인 질문을 함께 표시한다', (tester) async {
      await _pump(
        tester,
        const DiaryInsightsDto(
          schemaVersion: 3,
          dataScope: DiaryDataScopeDto(
            evidenceLevel: 'RICH',
            summary: '아이의 직접 발화와 별도 그림 관찰을 함께 사용했어요.',
          ),
          sessionObservations: [
            DiarySessionObservationDto(
              title: '친구와의 시간을 중요하게 느꼈을 가능성',
              description: '친구와 함께한 장면과 아이의 말이 이어졌어요.',
              insightType: 'SESSION_HYPOTHESIS',
              hypothesis: '친구와의 시간이 기억에 남았을 수 있어요.',
              alternativeExplanations: ['그리기 쉬운 장면을 골랐을 수도 있어요.'],
              clarificationQuestion: '친구와 있었을 때 어떤 점이 가장 좋았어?',
            ),
          ],
        ),
      );

      expect(find.text('그림과 대화에서 생각해 볼 수 있는 가능성'), findsOneWidget);
      expect(find.text('친구와의 시간이 기억에 남았을 수 있어요.'), findsOneWidget);
      expect(find.text('다르게 볼 수도 있어요'), findsOneWidget);
      expect(find.textContaining('친구와 있었을 때 어떤 점이 가장 좋았어?'), findsOneWidget);
    });
  });
}

Future<void> _pump(WidgetTester tester, DiaryInsightsDto insights) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: DiaryReportV3Body(insights: insights),
            ),
          ),
        ),
      ),
    );

DiaryInsightsDto _limitedInsights() => const DiaryInsightsDto(
  schemaVersion: 3,
  dataScope: DiaryDataScopeDto(
    evidenceLevel: 'LIMITED',
    summary: '그림과 선택 감정을 중심으로 정리했어요.',
    skippedCount: 2,
    visualObservationCount: 1,
  ),
  drawingObservations: [
    DiaryDrawingObservationDto(text: '노란색 별 모양이 보여요.', confidence: 'HIGH'),
  ],
  sessionObservations: [
    DiarySessionObservationDto(
      title: '가능성',
      description: '이번 활동에서 더 확인해 볼 수 있어요.',
      insightType: 'SESSION_HYPOTHESIS',
      hypothesis: '아이의 마음이 불편했을 수 있어요.',
      alternativeExplanations: ['그냥 그 색을 좋아했을 수도 있어요.'],
      clarificationQuestion: '그때 어떤 마음이었어?',
    ),
  ],
  unknownItems: [
    DiaryUnknownItemDto(code: 'EVENT_CONTEXT', text: '무슨 일이 있었는지는 확인하지 못했어요.'),
  ],
);

Map<String, Object?> _v3Fixture() => {
  'schemaVersion': 3,
  'dataScope': {
    'evidenceLevel': 'RICH',
    'summary': '확정된 발화와 그림 관찰을 함께 사용했어요.',
    'confirmedVoiceCount': 1,
    'optionAnswerCount': 0,
    'skippedCount': 0,
    'sttConfirmationCount': 0,
    'visualObservationCount': 1,
  },
  'storyComponents': [
    {
      'componentType': 'EVENT',
      'confirmationStatus': 'CONFIRMED',
      'text': '친구와 공원에서 놀았어요.',
      'evidenceRefs': [
        {'kind': 'QA_ANSWER', 'id': '22'},
      ],
    },
    {
      'componentType': 'EMOTION',
      'confirmationStatus': 'UNKNOWN',
      'text': null,
      'evidenceRefs': <Object?>[],
    },
  ],
  'drawingObservations': [
    {
      'text': '두 사람이 나란히 있어요.',
      'confidence': 'HIGH',
      'childConfirmed': true,
      'evidenceRefs': [
        {'kind': 'DRAWING_ASSET', 'id': '9'},
      ],
    },
  ],
  'transcript': [
    {
      'questionMessageId': 11,
      'answerMessageId': 22,
      'questionText': '누구와 함께 있었어?',
      'answerText': '친구와 있었어요.',
      'responseType': 'VOICE',
      'sttStatus': 'SUCCESS',
      'audioDurationMs': 4200,
      'audioAvailable': true,
      'audioUrl': '/api/v1/conversation-messages/22/audio',
      'elicitationType': 'OPEN_INVITATION',
      'createdAt': '2026-08-09T10:15:00',
    },
  ],
};
