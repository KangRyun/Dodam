import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/report/data/dto/report_dtos.dart';
import 'package:dodam/features/report/domain/repositories/report_repository.dart';
import 'package:dodam/features/report/presentation/screens/report_screen.dart';
import 'package:dodam/features/report/presentation/widgets/report_mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('production mascot 3종은 bundle에서 480×560으로 decode된다', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final path in [
        ReportMascotAssets.intro,
        ReportMascotAssets.observe,
        ReportMascotAssets.complete,
      ]) {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 480, reason: path);
        expect(frame.image.height, 560, reason: path);
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  testWidgets('completed Report는 일반형 Hero와 세 mascot을 장식으로 표시한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpReport(tester, report: _fullReport());

    expect(find.text('그림 속 이야기를 함께 돌아볼까요?'), findsOneWidget);
    expect(find.text('돌아보기 친구가 아이의 그림과 이야기를 차근차근 정리했어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-mascot-intro')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-mascot-observe')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('report-mascot-complete')),
      findsOneWidget,
    );
    expect(find.text('민지'), findsNothing);
    expect(find.text('6세'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('그림 속 이야기를 함께 돌아볼까요')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('mascot|마스코트')), findsNothing);
    semantics.dispose();
  });

  testWidgets('mascot asset decode 실패는 fallback만 표시하고 본문과 CTA를 유지한다', (
    tester,
  ) async {
    await _pumpReport(
      tester,
      report: _fullReport(),
      assetBundle: _FailingMascotBundle(),
    );

    expect(
      find.byKey(const ValueKey('report-mascot-fallback')),
      findsNWidgets(3),
    );
    expect(find.text('편안하게 대화했어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-home-cta')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('모든 Report section은 DTO 원문과 flat notes를 그대로 매핑한다', (
    tester,
  ) async {
    await _pumpReport(tester, report: _fullReport());

    expect(find.text('동생이랑 놀아서 좋았어요'), findsOneWidget);
    expect(find.textContaining('우리 동생이야.'), findsOneWidget);
    expect(find.text('사람, 집'), findsOneWidget);
    expect(find.text('잠시 멈춘 뒤 다시 그렸어요.'), findsOneWidget);
    expect(find.text('색을 여러 번 덧칠했어요.'), findsOneWidget);
    expect(find.text('멈춤'), findsOneWidget);
    expect(find.text('4회'), findsOneWidget);
    expect(find.text('지우기'), findsOneWidget);
    expect(find.text('2회'), findsOneWidget);
    expect(find.text('평균 필압'), findsOneWidget);
    expect(find.text('0.62'), findsOneWidget);
    expect(find.text('질문'), findsOneWidget);
    expect(find.text('5개'), findsOneWidget);
    expect(find.text('대답'), findsOneWidget);
    expect(find.text('4개'), findsOneWidget);
    expect(find.text('건너뜀'), findsOneWidget);
    expect(find.text('1개'), findsOneWidget);
    expect(find.text('기쁨'), findsOneWidget);
    expect(find.text('어떤 부분이 좋아?'), findsOneWidget);
    expect(find.textContaining('진단이 아닌 관찰 참고 자료'), findsOneWidget);
    expect(find.textContaining('집에서 관찰'), findsNothing);
    expect(find.textContaining('나무에서 관찰'), findsNothing);
    expect(find.textContaining('사람에서 관찰'), findsNothing);
  });

  testWidgets('통계의 null 값만 숨기고 summary는 유지한다', (tester) async {
    await _pumpReport(
      tester,
      report: _fullReport(
        conversation: const ReportConversationSummaryDto(
          questionCount: 5,
          answeredCount: null,
          skippedCount: null,
          summary: '질문 수만 제공된 요약이에요.',
        ),
      ),
    );

    expect(find.text('질문'), findsOneWidget);
    expect(find.text('5개'), findsOneWidget);
    expect(find.text('대답'), findsNothing);
    expect(find.text('건너뜀'), findsNothing);
    expect(find.text('질문 수만 제공된 요약이에요.'), findsOneWidget);
  });

  testWidgets('선택 감정·guide·limitations가 없으면 해당 내용만 숨긴다', (tester) async {
    await _pumpReport(
      tester,
      report: _fullReport(
        expression: const ReportChildExpressionDto(
          selectedEmotions: [],
          expressedEmotionText: '오늘 있었던 일을 말했어요.',
          representativeUtterances: [],
        ),
        guide: const [],
        limitations: const [],
      ),
    );

    expect(find.text('아이가 선택한 감정'), findsNothing);
    expect(
      find.byKey(const ValueKey('report-conversation-guide')),
      findsNothing,
    );
    // limitations가 비면 §11 섹션만 숨는다. §1 비진단 안내는 고정 필드라 유지된다.
    expect(find.byKey(const ValueKey('report-limitations')), findsNothing);
    expect(find.text('오늘 있었던 일을 말했어요.'), findsOneWidget);
  });

  testWidgets('모든 관찰 데이터가 비면 기존 no-observations 계약을 유지한다', (tester) async {
    await _pumpReport(
      tester,
      report: _fullReport(
        expression: const ReportChildExpressionDto(
          selectedEmotions: [],
          expressedEmotionText: null,
          representativeUtterances: [],
        ),
        facts: null,
        conversation: null,
        guide: const [],
      ),
    );

    expect(
      find.byKey(const ValueKey('report-no-observations')),
      findsOneWidget,
    );
    expect(find.text('아직 표시할 관찰 기록이 없어요.'), findsOneWidget);
  });

  testWidgets('일반 그림은 단일 인증 preview를 유지하고 history를 조회하지 않는다', (tester) async {
    final activityRepository = _ActivityRepository();
    await _pumpReport(
      tester,
      report: _fullReport(),
      activityRepository: activityRepository,
    );

    expect(find.byKey(const ValueKey('report-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('htp-report-gallery')), findsNothing);
    expect(activityRepository.requests, isEmpty);
  });

  testWidgets('HTP는 기존 gallery를 shell 안에서 HOUSE→TREE→PERSON으로 유지한다', (
    tester,
  ) async {
    final activityRepository = _ActivityRepository(
      activities: [_htpActivity()],
    );
    await _pumpReport(
      tester,
      report: _fullReport(isHtp: true),
      activityRepository: activityRepository,
    );

    expect(find.byKey(const ValueKey('htp-report-gallery')), findsOneWidget);
    final labels = [
      for (final element
          in find
              .byWidgetPredicate(
                (widget) =>
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'htp-report-preview-label-',
                    ),
              )
              .evaluate())
        ((element.widget.key! as ValueKey<String>).value.split('-').last),
    ];
    expect(labels, ['HOUSE', 'TREE', 'PERSON']);
    expect(activityRepository.requests, [(3, 0)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면 section의 시각적 순서는 확정 계약과 일치한다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await _pumpReport(tester, report: _fullReport());

    // 계약 §11 확정 섹션 순서(단일 세로 스크롤).
    final keys = [
      'report-mascot-intro',
      'report-non-diagnostic-notice',
      'report-activity-info',
      'report-drawings-section',
      'report-child-expression',
      'report-conversation-summary',
      'report-activity-facts',
      'report-conversation-guide',
      'report-limitations',
      'report-save-pdf',
    ];
    final tops = [
      for (final key in keys) tester.getTopLeft(find.byKey(ValueKey(key))).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.byKey(const ValueKey('report-small-layout')), findsOneWidget);
  });

  testWidgets('새 섹션까지 포함한 시각적 순서가 계약 §11과 일치한다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await _pumpReport(
      tester,
      report: _fullReport(
        publicInterpretations: const [
          ReportInterpretationDto(
            category: 'RELATIONSHIP',
            title: '가족과의 연결',
            tendencyText: '가족에게 의지하려는 경향이 보일 수 있습니다.',
            scopeText: '이번 그림에서 나타난 가능성입니다.',
            homeObservationGuide: '보호자의 확인을 구하는지 살펴봐 주세요.',
            evidenceRefs: [101],
          ),
        ],
        evidenceItems: const [
          ReportEvidenceItemDto(
            evidenceId: 101,
            sourceType: 'CHILD_ANSWER',
            text: '집에는 우리 가족이 산다고 답했어요.',
          ),
        ],
        subjectReports: const [
          ReportSubjectReportDto(
            subjectType: 'HOUSE',
            imageUrl: '/api/v1/drawing-assets/house/file',
            visionObservations: ['지붕이 커요.'],
            qaPairs: [],
            interpretationRefs: [0],
          ),
        ],
        observedFeatures: const [
          ReportObservedFeatureDto(
            title: '집을 크게 그렸어요',
            description: '종이 가운데에 집을 크게 그렸어요.',
            evidenceSummary: '그림에서 확인했어요.',
          ),
        ],
        parentGuides: const [
          ReportParentGuideDto(
            guideType: 'DRAWING_CONVERSATION',
            items: ['그림에서 무엇을 그렸는지 물어봐 주세요.'],
          ),
          ReportParentGuideDto(
            guideType: 'DAILY_PARENTING',
            items: ['하루 한 번 이야기를 들어 주세요.'],
          ),
          ReportParentGuideDto(
            guideType: 'HOME_OBSERVATION',
            items: ['새로운 곳에서 어떻게 반응하는지 살펴봐 주세요.'],
          ),
        ],
        references: const [
          ReportReferenceDto(title: '그림 심리의 이해', url: null),
        ],
      ),
    );

    // 표지·비진단 → 한눈에 → 주요 경향 → 집·나무·사람 그림 → 주제별 관찰과 문답
    // → 아이의 표현·대화 요약 → 이런 모습이 보였어요 → 객관 기록
    // → 그림 대화·육아 조언·가정 관찰 → 한계·참고 → PDF.
    final keys = [
      'report-mascot-intro',
      'report-non-diagnostic-notice',
      'report-activity-info',
      'report-interpretations',
      'report-drawings-section',
      'report-subject-observations',
      'report-child-expression',
      'report-conversation-summary',
      'report-observed-features',
      'report-activity-facts',
      'report-parent-guide-DRAWING_CONVERSATION',
      'report-parent-guide-DAILY_PARENTING',
      'report-parent-guide-HOME_OBSERVATION',
      'report-limitations',
      'report-save-pdf',
    ];
    final tops = [
      for (final key in keys) tester.getTopLeft(find.byKey(ValueKey(key))).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('900px breakpoint는 wide key와 단일 세로 섹션 순서를 유지한다', (
    tester,
  ) async {
    _setViewport(tester, const Size(900, 1000));
    await _pumpReport(tester, report: _fullReport());

    expect(find.byKey(const ValueKey('report-wide-layout')), findsOneWidget);
    // 재구성 후에는 폭과 무관하게 계약 §11 순서대로 세로로 쌓는다.
    final activityY = tester
        .getTopLeft(find.byKey(const ValueKey('report-activity-info')))
        .dy;
    final factsY = tester
        .getTopLeft(find.byKey(const ValueKey('report-activity-facts')))
        .dy;
    expect(factsY, greaterThan(activityY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppTopBar back을 실제 tap하면 이전 화면으로 한 번 복귀한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: AppRoutes.guardianHome,
        routes: {
          AppRoutes.guardianHome: (_) => const Scaffold(
            body: Text('리포트 이전 화면', key: ValueKey('report-previous-screen')),
          ),
          AppRoutes.report('501'): (_) => ReportScreen(
            reportId: '501',
            repository: _ReportRepository(_fullReport()),
            activityRepository: _ActivityRepository(),
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(
      find.byKey(const ValueKey('report-previous-screen')),
    );
    Navigator.of(context).pushNamed(AppRoutes.report('501'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('report-previous-screen')),
      findsOneWidget,
    );
    expect(find.text('관찰 리포트'), findsNothing);
  });

  testWidgets('publicInterpretations는 category 순서로 카드를 그리고 근거를 라벨로 편다', (
    tester,
  ) async {
    await _pumpReport(
      tester,
      report: _fullReport(
        publicInterpretations: const [
          ReportInterpretationDto(
            category: 'EMOTION',
            title: '감정 표현',
            tendencyText: '감정을 적극적으로 드러내는 경향이 보일 수 있습니다.',
            scopeText: '이번 그림 활동에서 나타난 가능성입니다.',
            homeObservationGuide: '집에서도 감정을 말로 표현하는지 살펴봐 주세요.',
            evidenceRefs: [],
          ),
          ReportInterpretationDto(
            category: 'RELATIONSHIP',
            title: '가족과의 연결',
            tendencyText: '가족에게 정서적으로 의지하려는 경향이 보일 수 있습니다.',
            scopeText: '이번 그림에서 나타난 가능성입니다.',
            homeObservationGuide: '보호자의 확인을 반복해서 구하는지 살펴봐 주세요.',
            evidenceRefs: [101],
          ),
        ],
        evidenceItems: const [
          ReportEvidenceItemDto(
            evidenceId: 101,
            sourceType: 'CHILD_ANSWER',
            text: '집에는 우리 가족이 산다고 답했어요.',
          ),
        ],
      ),
    );

    expect(find.byKey(const ValueKey('report-interpretations')), findsOneWidget);
    // RELATIONSHIP이 EMOTION보다 먼저 온다.
    final relationshipY = tester.getTopLeft(find.text('가족과의 연결')).dy;
    final emotionY = tester.getTopLeft(find.text('감정 표현')).dy;
    expect(relationshipY, lessThan(emotionY));
    expect(find.textContaining('의지하려는 경향이 보일 수 있습니다'), findsOneWidget);
    expect(find.text('이번 그림에서 나타난 가능성입니다.'), findsOneWidget);
    expect(find.textContaining('보호자의 확인을 반복해서'), findsOneWidget);

    // 근거는 접혀 있다가 라벨로만 펼쳐지고, 코드값은 노출하지 않는다.
    await tester.ensureVisible(find.text('근거 보기').first);
    await tester.tap(find.text('근거 보기').first);
    await tester.pumpAndSettle();
    expect(find.text('아이의 답변'), findsOneWidget);
    expect(find.text('집에는 우리 가족이 산다고 답했어요.'), findsOneWidget);
    expect(find.textContaining('CHILD_ANSWER'), findsNothing);
    expect(find.textContaining('101'), findsNothing);
  });

  testWidgets('subjectReports는 HOUSE→TREE→PERSON으로 문답 상태 문구를 표시한다', (
    tester,
  ) async {
    await _pumpReport(
      tester,
      report: _fullReport(
        subjectReports: const [
          ReportSubjectReportDto(
            subjectType: 'PERSON',
            imageUrl: null,
            visionObservations: ['사람을 크게 그렸어요.'],
            qaPairs: [],
            interpretationRefs: [],
          ),
          ReportSubjectReportDto(
            subjectType: 'HOUSE',
            imageUrl: null,
            visionObservations: [],
            qaPairs: [
              ReportQaPairDto(
                question: '이 집에는 누가 살아요?',
                answer: null,
                state: 'ANSWERED',
                inputType: 'TEXT',
                sttNeedsConfirmation: false,
                isRepresentative: true,
              ),
              ReportQaPairDto(
                question: '문은 어디 있어요?',
                answer: null,
                state: 'SKIPPED',
                inputType: 'TEXT',
                sttNeedsConfirmation: false,
                isRepresentative: true,
              ),
              ReportQaPairDto(
                question: '누구랑 살아요?',
                answer: '가족이요',
                state: 'ANSWERED',
                inputType: 'VOICE',
                sttNeedsConfirmation: true,
                isRepresentative: true,
              ),
            ],
            interpretationRefs: [],
          ),
        ],
      ),
    );

    final houseY = tester
        .getTopLeft(find.byKey(const ValueKey('report-subject-HOUSE')))
        .dy;
    final personY = tester
        .getTopLeft(find.byKey(const ValueKey('report-subject-PERSON')))
        .dy;
    expect(houseY, lessThan(personY));
    expect(find.textContaining('답하지 않았어요'), findsOneWidget);
    expect(find.textContaining('이 질문은 건너뛰었어요'), findsOneWidget);
    expect(find.text('음성 인식 내용을 확인해 주세요'), findsOneWidget);
    expect(find.text('사람을 크게 그렸어요.'), findsOneWidget);
  });

  testWidgets('subjectReports 이미지가 있으면 세 장을 계약 순서로 보여주고 활동기록을 조회하지 않는다', (
    tester,
  ) async {
    final activityRepository = _ActivityRepository(
      activities: [_htpActivity()],
    );
    await _pumpReport(
      tester,
      report: _fullReport(
        isHtp: true,
        subjectReports: const [
          ReportSubjectReportDto(
            subjectType: 'PERSON',
            imageUrl: '/api/v1/drawing-assets/person/file',
            visionObservations: [],
            qaPairs: [],
            interpretationRefs: [],
          ),
          ReportSubjectReportDto(
            subjectType: 'HOUSE',
            imageUrl: '/api/v1/drawing-assets/house/file',
            visionObservations: [],
            qaPairs: [],
            interpretationRefs: [],
          ),
          ReportSubjectReportDto(
            subjectType: 'TREE',
            imageUrl: '/api/v1/drawing-assets/tree/file',
            visionObservations: [],
            qaPairs: [],
            interpretationRefs: [],
          ),
        ],
      ),
      activityRepository: activityRepository,
    );

    expect(find.byKey(const ValueKey('report-subject-gallery')), findsOneWidget);
    final tops = [
      for (final subject in ['HOUSE', 'TREE', 'PERSON'])
        tester
            .getTopLeft(find.byKey(ValueKey('report-subject-image-$subject')))
            .dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    // 계약 데이터가 있으면 활동기록 우회 조회도, 단일 preview도 쓰지 않는다.
    expect(activityRepository.requests, isEmpty);
    expect(find.byKey(const ValueKey('htp-report-gallery')), findsNothing);
    expect(find.byKey(const ValueKey('report-image')), findsNothing);
    expect(find.text('집·나무·사람 그림'), findsOneWidget);
  });

  testWidgets('subjectReports에 이미지가 없으면 기존 HTP 활동기록 gallery로 물러난다', (
    tester,
  ) async {
    final activityRepository = _ActivityRepository(
      activities: [_htpActivity()],
    );
    await _pumpReport(
      tester,
      report: _fullReport(
        isHtp: true,
        subjectReports: const [
          ReportSubjectReportDto(
            subjectType: 'HOUSE',
            imageUrl: null,
            visionObservations: ['지붕이 커요.'],
            qaPairs: [],
            interpretationRefs: [],
          ),
        ],
      ),
      activityRepository: activityRepository,
    );

    expect(find.byKey(const ValueKey('report-subject-gallery')), findsNothing);
    expect(find.byKey(const ValueKey('htp-report-gallery')), findsOneWidget);
    // 그림이 없어도 관찰·문답 섹션은 그대로 뜬다.
    expect(find.text('지붕이 커요.'), findsOneWidget);
  });

  testWidgets('interpretationRefs는 화면 정렬이 아니라 응답 배열 인덱스로 푼다', (tester) async {
    await _pumpReport(
      tester,
      report: _fullReport(
        // 응답 순서: [0]=EMOTION, [1]=RELATIONSHIP. 화면은 RELATIONSHIP을
        // 먼저 그리므로, 인덱스를 화면 순서로 풀면 참조가 뒤바뀐다.
        publicInterpretations: const [
          ReportInterpretationDto(
            category: 'EMOTION',
            title: '감정 표현',
            tendencyText: '감정을 드러내는 경향이 보일 수 있습니다.',
            scopeText: '이번 활동에서 나타난 가능성입니다.',
            homeObservationGuide: '집에서도 살펴봐 주세요.',
            evidenceRefs: [],
          ),
          ReportInterpretationDto(
            category: 'RELATIONSHIP',
            title: '가족과의 연결',
            tendencyText: '가족에게 의지하려는 경향이 보일 수 있습니다.',
            scopeText: '이번 그림에서 나타난 가능성입니다.',
            homeObservationGuide: '보호자의 확인을 구하는지 살펴봐 주세요.',
            evidenceRefs: [],
          ),
        ],
        subjectReports: const [
          ReportSubjectReportDto(
            subjectType: 'HOUSE',
            imageUrl: null,
            visionObservations: ['지붕이 커요.'],
            qaPairs: [],
            interpretationRefs: [0, 9, -1],
          ),
        ],
      ),
    );

    final card = find.byKey(const ValueKey('report-subject-HOUSE'));
    expect(
      find.descendant(of: card, matching: find.text('감정 표현')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('가족과의 연결')),
      findsNothing,
    );
    // 범위를 벗어난 참조는 조용히 버린다.
    expect(tester.takeException(), isNull);
    // 경향 문구는 카드 밖(주제 섹션)으로 새어 나오지 않는다.
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('경향이 보일 수 있습니다'),
      ),
      findsNothing,
    );
  });

  testWidgets('observedFeatures는 "이런 모습이 보였어요" 섹션으로 뜬다', (tester) async {
    await _pumpReport(
      tester,
      report: _fullReport(
        observedFeatures: const [
          ReportObservedFeatureDto(
            title: '집을 크게 그렸어요',
            description: '종이 가운데에 집을 크게 그렸어요.',
            evidenceSummary: '그림에서 확인했어요.',
          ),
        ],
      ),
    );

    expect(
      find.byKey(const ValueKey('report-observed-features')),
      findsOneWidget,
    );
    expect(find.text('이런 모습이 보였어요'), findsOneWidget);
    expect(find.text('집을 크게 그렸어요'), findsOneWidget);
    expect(find.text('종이 가운데에 집을 크게 그렸어요.'), findsOneWidget);
    expect(find.text('그림에서 확인했어요.'), findsOneWidget);
  });

  testWidgets('observedFeatures가 비면 섹션이 조용히 숨고 안내 문구를 만들지 않는다', (
    tester,
  ) async {
    await _pumpReport(tester, report: _fullReport());

    expect(
      find.byKey(const ValueKey('report-observed-features')),
      findsNothing,
    );
    expect(find.text('이런 모습이 보였어요'), findsNothing);
    // 빈 배열은 오류가 아니라 숨김이다 — "데이터 없음" 같은 문구를 띄우지 않는다.
    expect(find.textContaining('데이터'), findsNothing);
    expect(find.textContaining('없어요'), findsNothing);
  });

  testWidgets('childDisplayName이 있으면 표지에 표시한다', (tester) async {
    await _pumpReport(tester, report: _fullReport(childDisplayName: '민준'));

    expect(find.text('민준'), findsOneWidget);
  });

  testWidgets('childDisplayName이 없으면 표지 pill이 빠진다', (tester) async {
    await _pumpReport(tester, report: _fullReport());

    expect(find.text('민준'), findsNothing);
    expect(find.text('리포트 v2'), findsOneWidget);
  });

  testWidgets('parentGuides는 guideType별 제목으로 정렬해 나눈다', (tester) async {
    await _pumpReport(
      tester,
      report: _fullReport(
        parentGuides: const [
          ReportParentGuideDto(
            guideType: 'DAILY_PARENTING',
            items: ['하루 한 번 아이의 이야기를 들어 주세요.'],
          ),
          ReportParentGuideDto(
            guideType: 'DRAWING_CONVERSATION',
            items: ['그림에서 무엇을 그렸는지 물어봐 주세요.'],
          ),
          ReportParentGuideDto(
            guideType: 'PROFESSIONAL_SUPPORT',
            items: ['더 이야기 나누고 싶을 때 상담을 참고할 수 있어요.'],
          ),
        ],
      ),
    );

    expect(find.text('그림으로 대화해 보세요'), findsOneWidget);
    expect(find.text('일상에서 이렇게 도와주세요'), findsOneWidget);
    expect(find.text('도움이 필요할 때'), findsOneWidget);
    // DRAWING_CONVERSATION이 DAILY_PARENTING보다 먼저 온다.
    final drawingY = tester.getTopLeft(find.text('그림으로 대화해 보세요')).dy;
    final dailyY = tester.getTopLeft(find.text('일상에서 이렇게 도와주세요')).dy;
    expect(drawingY, lessThan(dailyY));
  });

  testWidgets('references는 §11 섹션에 표시되고 nonDiagnosticNotice가 없으면 카드가 숨는다', (
    tester,
  ) async {
    await _pumpReport(
      tester,
      report: _fullReport(
        nonDiagnosticNotice: null,
        references: const [
          ReportReferenceDto(title: '그림 심리의 이해', url: 'https://example.test'),
        ],
      ),
    );

    expect(
      find.byKey(const ValueKey('report-non-diagnostic-notice')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('report-limitations')), findsOneWidget);
    expect(find.text('그림 심리의 이해'), findsOneWidget);
  });

  testWidgets('재구성 화면은 금지어(위험·이상·문제·정상)를 노출하지 않는다', (tester) async {
    await _pumpReport(
      tester,
      report: _fullReport(
        publicInterpretations: const [
          ReportInterpretationDto(
            category: 'ADAPTATION',
            title: '새로운 환경 적응',
            tendencyText: '새 상황에서 천천히 살펴보는 경향이 보일 수 있습니다.',
            scopeText: '이번 활동에서 나타난 가능성입니다.',
            homeObservationGuide: '새로운 곳에서 어떻게 반응하는지 살펴봐 주세요.',
            evidenceRefs: [],
          ),
        ],
        parentGuides: const [
          ReportParentGuideDto(
            guideType: 'PROFESSIONAL_SUPPORT',
            items: ['더 이야기하고 싶을 때 참고할 수 있어요.'],
          ),
        ],
      ),
    );

    for (final banned in ['위험', '이상', '문제', '정상', '비정상']) {
      expect(find.textContaining(banned), findsNothing, reason: banned);
    }
  });

  for (final viewport in const [
    (name: '320×640', size: Size(320, 640), scale: 1.0),
    (name: '390×844', size: Size(390, 844), scale: 1.0),
    (name: '휴대폰 가로', size: Size(844, 390), scale: 1.0),
    (name: '800×1280', size: Size(800, 1280), scale: 1.0),
    (name: '1600×1000', size: Size(1600, 1000), scale: 1.0),
    (name: '낮은 높이', size: Size(600, 320), scale: 1.0),
    (name: 'text scale 2.0', size: Size(390, 844), scale: 2.0),
  ]) {
    testWidgets('${viewport.name}에서 단일 스크롤로 최하단 CTA를 실제 tap한다', (tester) async {
      _setViewport(tester, viewport.size);
      await _pumpReport(
        tester,
        report: _longReport(),
        textScale: viewport.scale,
      );

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      final cta = find.byKey(const ValueKey('report-home-cta'));
      final scrollable = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      await tester.scrollUntilVisible(cta, 500, scrollable: scrollable);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('guardian-home-target')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpReport(
  WidgetTester tester, {
  required ReportDetailDto report,
  ActivityRepository? activityRepository,
  AssetBundle? assetBundle,
  double textScale = 1,
}) async {
  Widget app = MaterialApp(
    initialRoute: AppRoutes.report('501'),
    routes: {
      AppRoutes.report('501'): (_) => MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: ReportScreen(
          reportId: '501',
          repository: _ReportRepository(report),
          activityRepository: activityRepository ?? _ActivityRepository(),
        ),
      ),
      AppRoutes.guardianHome: (_) => const Scaffold(
        body: Center(
          child: Text('보호자 홈', key: ValueKey('guardian-home-target')),
        ),
      ),
    },
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
  );
  if (assetBundle != null) {
    app = DefaultAssetBundle(bundle: assetBundle, child: app);
  }
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

ReportDetailDto _fullReport({
  bool isHtp = false,
  ReportChildExpressionDto? expression = const ReportChildExpressionDto(
    selectedEmotions: ['JOY'],
    expressedEmotionText: '동생이랑 놀아서 좋았어요',
    representativeUtterances: [
      ReportUtteranceDto(
        messageId: 804,
        text: '우리 동생이야.',
        source: 'STT',
        sttNeedsConfirmation: false,
      ),
    ],
  ),
  ReportActivityFactsDto? facts = const ReportActivityFactsDto(
    detectedObjects: ['사람', '집'],
    drawingDurationMs: 1320000,
    pauseCount: 4,
    eraseCount: 2,
    pressureAvailable: true,
    pressureValue: 0.62,
    notes: ['잠시 멈춘 뒤 다시 그렸어요.', '색을 여러 번 덧칠했어요.'],
  ),
  ReportConversationSummaryDto? conversation =
      const ReportConversationSummaryDto(
        questionCount: 5,
        answeredCount: 4,
        skippedCount: 1,
        summary: '편안하게 대화했어요.',
      ),
  List<String> guide = const ['어떤 부분이 좋아?'],
  List<String> limitations = const ['이 리포트는 진단이 아닌 관찰 참고 자료입니다.'],
  String? nonDiagnosticNotice =
      '이 리포트는 아이가 그림을 그리고 대화한 과정에서 나타난 특징을 정리한 자료예요.',
  List<ReportInterpretationDto> publicInterpretations = const [],
  List<ReportEvidenceItemDto> evidenceItems = const [],
  List<ReportSubjectReportDto> subjectReports = const [],
  List<ReportObservedFeatureDto> observedFeatures = const [],
  List<ReportParentGuideDto> parentGuides = const [],
  List<ReportReferenceDto> references = const [],
  String? childDisplayName,
}) => ReportDetailDto(
  reportId: 501,
  reportVersion: 2,
  reportStatus: 'COMPLETED',
  drawingSession: ReportDrawingSessionDto(
    drawingSessionId: 120,
    childId: 3,
    drawingTypeCode: isHtp ? 'HTP' : 'ART_DIARY',
    drawingTypeName: isHtp ? 'HTP 검사' : '그림일기',
    title: '우리 가족',
    inputMethod: isHtp ? 'UPLOAD' : 'CANVAS',
    startedAt: '2026-08-03T09:40:00Z',
    completedAt: '2026-08-03T10:03:00Z',
    durationMs: 1380000,
  ),
  drawing: const ReportDrawingDto(
    finalImageUrl: '/api/v1/drawing-assets/general/file',
    thumbnailUrl: null,
  ),
  childExpression: expression,
  activityFacts: facts,
  conversationSummary: conversation,
  guardianConversationGuide: guide,
  limitations: limitations,
  activityType: isHtp ? 'HTP' : 'ART_DIARY',
  childDisplayName: childDisplayName,
  nonDiagnosticNotice: nonDiagnosticNotice,
  publicInterpretations: publicInterpretations,
  evidenceItems: evidenceItems,
  subjectReports: subjectReports,
  observedFeatures: observedFeatures,
  parentGuides: parentGuides,
  references: references,
  expertReview: const ReportExpertReviewDto(
    status: 'NOT_REQUESTED',
    available: false,
  ),
  createdAt: '2026-08-03T10:12:00Z',
);

ReportDetailDto _longReport() => _fullReport(
  facts: const ReportActivityFactsDto(
    detectedObjects: ['사람', '집', '나무', '구름'],
    drawingDurationMs: 1320000,
    pauseCount: 4,
    eraseCount: 2,
    pressureAvailable: true,
    notes: [
      '아이가 긴 이야기를 충분히 이어갈 수 있도록 줄 수를 제한하지 않는 관찰 문장입니다. '
          '작은 화면과 큰 글자에서도 자연스럽게 여러 줄로 표시되어야 합니다.',
      '관찰 내용은 HOUSE, TREE, PERSON 주제를 임의로 붙이지 않고 서버가 제공한 순서 그대로 표시합니다.',
    ],
  ),
  conversation: const ReportConversationSummaryDto(
    questionCount: 12,
    answeredCount: 10,
    skippedCount: 2,
    summary:
        '대화 요약은 길어져도 말줄임 없이 모든 내용을 보여 줍니다. '
        '화면 폭이 좁거나 글자 크기가 커져도 다음 section과 겹치지 않아야 합니다.',
  ),
  guide: const [
    '그림을 그리면서 가장 즐거웠던 순간을 아이의 속도에 맞춰 천천히 물어보세요.',
    '정답을 유도하지 말고 아이가 사용한 표현을 그대로 되짚어 주세요.',
  ],
);

ActivitySummaryDto _htpActivity() => ActivitySummaryDto(
  activityId: 77,
  title: 'HTP',
  drawingType: const ActivityDrawingTypeDto(code: 'HTP', name: 'HTP'),
  inputMethod: 'UPLOAD',
  sessionStatus: 'COMPLETED',
  selectedEmotions: const [],
  thumbnailUrl: null,
  analysisStatus: null,
  report: null,
  startedAt: '2026-08-03T00:00:00Z',
  completedAt: '2026-08-03T00:10:00Z',
  activityKind: 'HTP',
  htpAssessmentId: 7,
  htpStatus: 'COMPLETED',
  htpDrawings: const [
    HtpActivityDrawingDto(
      drawingSubject: 'HOUSE',
      drawingSessionId: 71,
      thumbnailUrl: '/api/v1/drawing-assets/house/file',
    ),
    HtpActivityDrawingDto(
      drawingSubject: 'TREE',
      drawingSessionId: 72,
      thumbnailUrl: '/api/v1/drawing-assets/tree/file',
    ),
    HtpActivityDrawingDto(
      drawingSubject: 'PERSON',
      drawingSessionId: 120,
      thumbnailUrl: '/api/v1/drawing-assets/person/file',
    ),
  ],
);

final class _ReportRepository implements ReportRepository {
  _ReportRepository(this.report);

  final ReportDetailDto report;

  @override
  Future<ReportDetailDto> getReport(int reportId) async => report;

  @override
  Future<Uint8List> downloadImage(String imageUrl) async => _validPng;

  @override
  Future<ReportGenerationStatusDto> getGenerationStatus(int reportId) =>
      throw UnimplementedError();

  @override
  Future<ReportGenerationStatusDto> regenerateReport(
    int reportId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  }) => throw UnimplementedError();

  @override
  Future<ReportExportDto> requestExport(
    int reportId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadExport(String downloadUrl) =>
      throw UnimplementedError();

  @override
  Future<AnalysisStatusDto> getAnalysisStatus(int analysisId) =>
      throw UnimplementedError();

  @override
  Future<AnalysisAcceptedDto> retryAnalysis(
    int analysisId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

final class _ActivityRepository implements ActivityRepository {
  _ActivityRepository({this.activities = const []});

  final List<ActivitySummaryDto> activities;
  final List<(int, int)> requests = [];

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async {
    requests.add((childId, filter.page));
    return ApiPage(
      content: activities,
      page: 0,
      size: 20,
      totalElements: activities.length,
      totalPages: 1,
      hasNext: false,
    );
  }

  @override
  Future<Uint8List> downloadImage(String url) async => _validPng;

  @override
  Future<void> deleteActivity(int activityId) => throw UnimplementedError();

  @override
  Future<ActivityDetailDto> getActivity(int activityId) =>
      throw UnimplementedError();

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) => throw UnimplementedError();
}

class _FailingMascotBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key.startsWith('assets/characters/report_mascot_')) {
      return Future<ByteData>.error(StateError('mascot decode failure'));
    }
    return rootBundle.load(key);
  }
}

final Uint8List _validPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
