import 'package:dodam/features/report/data/dto/report_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

/// REPORT-02 보호자 공개 계약(`docs/api/report-detail-guardian-contract.md` §2)
/// 그대로의 nested 응답을 파싱하는지 검증한다.
void main() {
  group('ReportDetailDto.fromJson', () {
    test('nested 계약 응답의 모든 섹션을 파싱한다', () {
      final report = ReportDetailDto.fromJson(_fullJson());

      expect(report.reportId, 500);
      expect(report.reportVersion, 1);
      expect(report.reportStatus, 'COMPLETED');
      expect(report.createdAt, '2026-07-21T02:06:00');

      final session = report.drawingSession!;
      expect(session.drawingSessionId, 100);
      expect(session.childId, 1);
      expect(session.drawingTypeCode, 'HOUSE_TREE_PERSON');
      expect(session.drawingTypeName, '집-나무-사람');
      expect(session.title, '우리 가족');
      expect(session.inputMethod, 'CANVAS');
      expect(session.durationMs, 300000);

      expect(report.drawing!.finalImageUrl, 'https://cdn.example/final.png');
      expect(report.drawing!.thumbnailUrl, 'https://cdn.example/thumb.png');

      final expression = report.childExpression!;
      expect(expression.selectedEmotions, ['HAPPY']);
      expect(expression.expressedEmotionText, '행복한 하루였어요');

      final facts = report.activityFacts!;
      expect(facts.detectedObjects, ['집']);
      expect(facts.drawingDurationMs, 295000);
      expect(facts.pauseCount, 4);
      expect(facts.eraseCount, 2);
      expect(facts.pressureAvailable, isTrue);
      expect(facts.notes, ['멈춤 4회 관찰']);

      final conversation = report.conversationSummary!;
      expect(conversation.questionCount, 5);
      expect(conversation.answeredCount, 4);
      expect(conversation.skippedCount, 1);
      expect(conversation.summary, '아이가 편안하게 대화했습니다');

      expect(report.guardianConversationGuide, ['오늘 그림에 대해 함께 이야기해 보세요']);
      expect(report.limitations, ['이 리포트는 진단이 아닙니다']);
      expect(report.expertReview!.status, 'NOT_REQUESTED');
      expect(report.expertReview!.available, isFalse);
    });

    test('구형 flat 필드(keyConversations 등)는 더 이상 읽지 않는다', () {
      final json = _fullJson()
        ..['keyConversations'] = [
          {'question': 'q', 'answer': 'a', 'answerType': 'VOICE'},
        ];

      final report = ReportDetailDto.fromJson(json);

      // childExpression 경로만 대표 발화의 출처다.
      expect(report.childExpression!.representativeUtterances, hasLength(1));
      expect(
        report.childExpression!.representativeUtterances.single.text,
        '친구랑 있어서 좋아',
      );
    });

    test('GENERATING 부분 응답처럼 nested 섹션이 없어도 안전하게 파싱한다', () {
      final report = ReportDetailDto.fromJson(const {
        'reportId': 500,
        'reportVersion': 1,
        'reportStatus': 'GENERATING',
        'drawingSession': null,
        'drawing': null,
        'childExpression': null,
        'activityFacts': null,
        'conversationSummary': null,
        'guardianConversationGuide': null,
        'limitations': null,
        'expertReview': null,
        'createdAt': null,
      });

      expect(report.reportStatus, 'GENERATING');
      expect(report.drawingSession, isNull);
      expect(report.drawing, isNull);
      expect(report.childExpression, isNull);
      expect(report.guardianConversationGuide, isEmpty);
      expect(report.limitations, isEmpty);
      expect(report.createdAt, isNull);
      expect(report.hasNoObservations, isTrue);
    });

    test('nullable 스칼라가 null이어도 파싱한다', () {
      final json = _fullJson()
        ..['drawingSession'] = {
          'drawingSessionId': 100,
          'childId': 1,
          'drawingTypeCode': null,
          'drawingTypeName': null,
          'title': null,
          'inputMethod': null,
          'startedAt': null,
          'completedAt': null,
          'durationMs': null,
        }
        ..['drawing'] = {'finalImageUrl': null, 'thumbnailUrl': null}
        ..['conversationSummary'] = {
          'questionCount': null,
          'answeredCount': null,
          'skippedCount': null,
          'summary': null,
        };

      final report = ReportDetailDto.fromJson(json);

      expect(report.drawingSession!.title, isNull);
      expect(report.drawingSession!.durationMs, isNull);
      expect(report.drawing!.finalImageUrl, isNull);
      expect(report.conversationSummary!.isEmpty, isTrue);
    });
  });

  group('재구성 계약 필드 (S15P11B209-875)', () {
    test('신규 필드가 없으면 빈 목록·null로 하위 호환된다', () {
      final report = ReportDetailDto.fromJson(_fullJson());

      expect(report.activityType, isNull);
      expect(report.childDisplayName, isNull);
      expect(report.nonDiagnosticNotice, isNull);
      expect(report.publicInterpretations, isEmpty);
      expect(report.evidenceItems, isEmpty);
      expect(report.subjectReports, isEmpty);
      expect(report.observedFeatures, isEmpty);
      expect(report.parentGuides, isEmpty);
      expect(report.references, isEmpty);
      expect(report.orderedParentGuides, isEmpty);
      expect(report.orderedSubjectReports, isEmpty);
      expect(report.subjectDrawings, isEmpty);
      expect(report.subjectDetails, isEmpty);
    });

    test('activityType·childDisplayName을 읽고 HTP를 판정한다', () {
      final report = ReportDetailDto.fromJson(
        _fullJson()
          ..['activityType'] = 'HTP'
          ..['childDisplayName'] = '민준',
      );

      expect(report.activityType, 'HTP');
      expect(report.childDisplayName, '민준');
      expect(report.isHtpActivity, isTrue);
    });

    test('activityType이 없으면 구형 drawingTypeCode로 HTP를 판정한다', () {
      final base = _fullJson();
      expect(ReportDetailDto.fromJson(base).isHtpActivity, isFalse);

      final htp = _fullJson()
        ..['drawingSession'] = {
          ...Map<String, dynamic>.from(base['drawingSession'] as Map),
          'drawingTypeCode': 'htp',
        };

      expect(ReportDetailDto.fromJson(htp).isHtpActivity, isTrue);
    });

    test('observedFeatures를 계약 §2-1 필드명으로 읽는다', () {
      final json = _fullJson()
        ..['observedFeatures'] = [
          {
            'title': '집을 크게 그렸어요',
            'description': '종이 가운데에 집을 크게 그렸어요.',
            'evidenceSummary': '그림에서 확인했어요.',
          },
          {'title': null, 'description': '나무를 여러 번 덧칠했어요.'},
        ];

      final features = ReportDetailDto.fromJson(json).observedFeatures;

      expect(features, hasLength(2));
      expect(features.first.title, '집을 크게 그렸어요');
      expect(features.first.description, '종이 가운데에 집을 크게 그렸어요.');
      expect(features.first.evidenceSummary, '그림에서 확인했어요.');
      expect(features.first.isEmpty, isFalse);
      expect(features.last.title, isNull);
      expect(features.last.evidenceSummary, isNull);
    });

    test('observedFeatures의 공백·비문자열 값은 값 없음으로 다룬다', () {
      final json = _fullJson()
        ..['observedFeatures'] = [
          {'title': '   ', 'description': 7, 'evidenceSummary': ''},
        ];

      final feature = ReportDetailDto.fromJson(json).observedFeatures.single;

      expect(feature.title, isNull);
      expect(feature.description, isNull);
      expect(feature.evidenceSummary, isNull);
      expect(feature.isEmpty, isTrue);
    });

    test('subjectDrawings·subjectDetails가 계약 순서로 나뉜다', () {
      final json = _fullJson()
        ..['subjectReports'] = [
          {'subjectType': 'PERSON', 'imageUrl': 'https://cdn.example/p.png'},
          {
            'subjectType': 'TREE',
            'imageUrl': '   ',
            'visionObservations': ['나무가 커요.'],
          },
          {'subjectType': 'HOUSE', 'imageUrl': 'https://cdn.example/h.png'},
        ];

      final report = ReportDetailDto.fromJson(json);

      expect(
        report.subjectDrawings.map((item) => item.subjectType),
        ['HOUSE', 'PERSON'],
      );
      expect(report.subjectDetails.map((item) => item.subjectType), ['TREE']);
      // 공백뿐인 URL은 그림이 없는 것으로 본다.
      expect(report.orderedSubjectReports[1].imageUrl, isNull);
    });

    test('evidenceItems의 sourceRef·derivedFrom 같은 모르는 키는 무시한다', () {
      final json = _fullJson()
        ..['evidenceItems'] = [
          {
            'evidenceId': 101,
            'sourceType': 'CHILD_ANSWER',
            'text': '가족이 산대요.',
            'sourceRef': {'kind': 'QA_ANSWER', 'id': '202'},
            'derivedFrom': null,
          },
        ]
        ..['unknownFutureSection'] = {'anything': true};

      final report = ReportDetailDto.fromJson(json);

      expect(report.evidenceItems.single.evidenceId, 101);
      expect(report.evidenceItems.single.text, '가족이 산대요.');
    });

    test('observedFeatures나 주제별 문답이 있으면 관찰 없음으로 보지 않는다', () {
      Map<String, dynamic> emptyReport() =>
          _fullJson()
            ..['childExpression'] = null
            ..['activityFacts'] = null
            ..['conversationSummary'] = null
            ..['guardianConversationGuide'] = <String>[];

      expect(ReportDetailDto.fromJson(emptyReport()).hasNoObservations, isTrue);
      expect(
        ReportDetailDto.fromJson(
          emptyReport()
            ..['observedFeatures'] = [
              {'description': '집을 크게 그렸어요.'},
            ],
        ).hasNoObservations,
        isFalse,
      );
      expect(
        ReportDetailDto.fromJson(
          emptyReport()
            ..['subjectReports'] = [
              {
                'subjectType': 'HOUSE',
                'qaPairs': [
                  {'question': '누가 살아요?', 'answer': '가족이요'},
                ],
              },
            ],
        ).hasNoObservations,
        isFalse,
      );
    });

    test('publicInterpretations·evidenceItems·subjectReports를 파싱한다', () {
      final json = _fullJson()
        ..['nonDiagnosticNotice'] = '진단이 아니라 관찰 참고 자료예요.'
        ..['publicInterpretations'] = [
          {
            'category': 'RELATIONSHIP',
            'title': '가족과의 연결',
            'tendencyText': '의지하려는 경향이 보일 수 있습니다.',
            'scopeText': '이번 활동에서 나타난 가능성입니다.',
            'homeObservationGuide': '살펴봐 주세요.',
            'evidenceRefs': [101, 102],
          },
        ]
        ..['evidenceItems'] = [
          {'evidenceId': 101, 'sourceType': 'CHILD_ANSWER', 'text': '가족이 산대요.'},
        ]
        ..['subjectReports'] = [
          {
            'subjectType': 'HOUSE',
            'imageUrl': 'https://cdn.example/house.png',
            'visionObservations': ['지붕이 커요.'],
            'qaPairs': [
              {
                'question': '누가 살아요?',
                'answer': '가족이요',
                'state': 'ANSWERED',
                'inputType': 'VOICE',
                'sttNeedsConfirmation': true,
                'isRepresentative': true,
              },
            ],
            'interpretationRefs': [0],
          },
        ]
        ..['parentGuides'] = [
          {
            'guideType': 'DAILY_PARENTING',
            'items': ['하루 한 번 이야기 들어 주세요.'],
          },
        ]
        ..['references'] = [
          {'title': '그림 심리의 이해', 'url': null},
        ];

      final report = ReportDetailDto.fromJson(json);

      expect(report.nonDiagnosticNotice, '진단이 아니라 관찰 참고 자료예요.');
      final interpretation = report.publicInterpretations.single;
      expect(interpretation.category, 'RELATIONSHIP');
      expect(interpretation.evidenceRefs, [101, 102]);
      expect(report.evidenceItems.single.sourceType, 'CHILD_ANSWER');
      final subject = report.subjectReports.single;
      expect(subject.subjectType, 'HOUSE');
      expect(subject.visionObservations, ['지붕이 커요.']);
      final qa = subject.qaPairs.single;
      expect(qa.inputType, 'VOICE');
      expect(qa.sttNeedsConfirmation, isTrue);
      expect(report.parentGuides.single.guideType, 'DAILY_PARENTING');
      expect(report.references.single.title, '그림 심리의 이해');
    });

    test('orderedSubjectReports·orderedParentGuides가 계약 순서로 정렬한다', () {
      final json = _fullJson()
        ..['subjectReports'] = [
          {'subjectType': 'PERSON'},
          {'subjectType': 'HOUSE'},
          {'subjectType': 'TREE'},
        ]
        ..['parentGuides'] = [
          {
            'guideType': 'PROFESSIONAL_SUPPORT',
            'items': ['a'],
          },
          {
            'guideType': 'DRAWING_CONVERSATION',
            'items': ['b'],
          },
        ];

      final report = ReportDetailDto.fromJson(json);

      expect(
        report.orderedSubjectReports.map((item) => item.subjectType),
        ['HOUSE', 'TREE', 'PERSON'],
      );
      expect(
        report.orderedParentGuides.map((item) => item.guideType),
        ['DRAWING_CONVERSATION', 'PROFESSIONAL_SUPPORT'],
      );
    });

    test('activityFacts 신규 수치와 플래그를 파싱한다', () {
      final json = _fullJson()
        ..['activityFacts'] = {
          'totalDurationSec': 420,
          'drawingDurationSec': 260,
          'pauseCount': 3,
          'undoCount': 2,
          'questionCount': 6,
          'answerCount': 5,
          'skipCount': 1,
          'detectedElementCount': 12,
          'pressureAvailable': true,
          'pressureValue': 0.62,
          'truncated': true,
          'aggregatedHtp': true,
        };

      final facts = ReportDetailDto.fromJson(json).activityFacts!;

      expect(facts.totalDurationSec, 420);
      expect(facts.undoCount, 2);
      expect(facts.detectedElementCount, 12);
      expect(facts.hasPressureValue, isTrue);
      expect(facts.pressureValue, 0.62);
      expect(facts.truncated, isTrue);
      expect(facts.aggregatedHtp, isTrue);
    });

    test('pressureAvailable만 true이고 값이 없으면 필압을 노출하지 않는다', () {
      final json = _fullJson()
        ..['activityFacts'] = {
          'pressureAvailable': true,
          'pressureValue': null,
        };

      final facts = ReportDetailDto.fromJson(json).activityFacts!;

      expect(facts.pressureAvailable, isTrue);
      expect(facts.hasPressureValue, isFalse);
    });
  });

  group('representativeUtterances', () {
    test('정상 항목을 순서대로 파싱한다', () {
      final report = ReportDetailDto.fromJson(_fullJson());
      final utterance = report.childExpression!.representativeUtterances.single;

      expect(utterance.messageId, 804);
      expect(utterance.text, '친구랑 있어서 좋아');
      expect(utterance.source, 'STT');
      expect(utterance.sttNeedsConfirmation, isFalse);
    });

    test('빈 배열이면 빈 목록이 된다', () {
      final json = _fullJson()
        ..['childExpression'] = {
          'selectedEmotions': <String>[],
          'expressedEmotionText': null,
          'representativeUtterances': <Object>[],
        };

      final report = ReportDetailDto.fromJson(json);

      expect(report.childExpression!.representativeUtterances, isEmpty);
      expect(report.childExpression!.isEmpty, isTrue);
    });

    test('representativeUtterances 키가 아예 없어도 빈 목록이 된다', () {
      final json = _fullJson()
        ..['childExpression'] = {'selectedEmotions': <String>[]};

      final report = ReportDetailDto.fromJson(json);

      expect(report.childExpression!.representativeUtterances, isEmpty);
    });

    test('messageId와 text가 null이어도 파싱하고 source 기본값은 TEXT다', () {
      final json = _fullJson()
        ..['childExpression'] = {
          'selectedEmotions': <String>[],
          'expressedEmotionText': null,
          'representativeUtterances': [
            {
              'messageId': null,
              'text': null,
              'source': null,
              'sttNeedsConfirmation': null,
            },
          ],
        };

      final utterance = ReportDetailDto.fromJson(
        json,
      ).childExpression!.representativeUtterances.single;

      expect(utterance.messageId, isNull);
      expect(utterance.text, isNull);
      expect(utterance.source, 'TEXT');
      expect(utterance.sttNeedsConfirmation, isFalse);
    });

    test('source=STT와 TEXT를 그대로 구분해 보존한다', () {
      final json = _fullJson()
        ..['childExpression'] = {
          'selectedEmotions': <String>[],
          'representativeUtterances': [
            {'messageId': 804, 'text': '음성', 'source': 'STT'},
            {'messageId': null, 'text': '음성인데 원본 없음', 'source': 'STT'},
            {'messageId': 805, 'text': '텍스트', 'source': 'TEXT'},
          ],
        };

      final utterances = ReportDetailDto.fromJson(
        json,
      ).childExpression!.representativeUtterances;

      expect(utterances.map((item) => item.source), ['STT', 'STT', 'TEXT']);
      expect(utterances.map((item) => item.messageId), [804, null, 805]);
    });
  });
}

/// 백엔드 `ReportDetailResponseJsonTest`의 golden 표본과 같은 모양.
Map<String, dynamic> _fullJson() => {
  'reportId': 500,
  'reportVersion': 1,
  'reportStatus': 'COMPLETED',
  'drawingSession': {
    'drawingSessionId': 100,
    'childId': 1,
    'drawingTypeCode': 'HOUSE_TREE_PERSON',
    'drawingTypeName': '집-나무-사람',
    'title': '우리 가족',
    'inputMethod': 'CANVAS',
    'startedAt': '2026-07-21T02:00:00',
    'completedAt': '2026-07-21T02:05:00',
    'durationMs': 300000,
  },
  'drawing': {
    'finalImageUrl': 'https://cdn.example/final.png',
    'thumbnailUrl': 'https://cdn.example/thumb.png',
  },
  'childExpression': {
    'selectedEmotions': ['HAPPY'],
    'expressedEmotionText': '행복한 하루였어요',
    'representativeUtterances': [
      {
        'messageId': 804,
        'text': '친구랑 있어서 좋아',
        'source': 'STT',
        'sttNeedsConfirmation': false,
      },
    ],
  },
  'activityFacts': {
    'detectedObjects': ['집'],
    'drawingDurationMs': 295000,
    'pauseCount': 4,
    'eraseCount': 2,
    'pressureAvailable': true,
    'notes': ['멈춤 4회 관찰'],
  },
  'conversationSummary': {
    'questionCount': 5,
    'answeredCount': 4,
    'skippedCount': 1,
    'summary': '아이가 편안하게 대화했습니다',
  },
  'guardianConversationGuide': ['오늘 그림에 대해 함께 이야기해 보세요'],
  'limitations': ['이 리포트는 진단이 아닙니다'],
  'expertReview': {'status': 'NOT_REQUESTED', 'available': false},
  'createdAt': '2026-07-21T02:06:00',
};
