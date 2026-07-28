import 'dart:async';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/report/data/dto/report_dtos.dart';
import 'package:dodam/features/report/domain/repositories/report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Activity Detail의 실제 reportId로 진입하고 Back으로 복귀한다', (tester) async {
    final reportRepository = _ReportRepository(report: _report(reportId: 777));
    await tester.pumpWidget(
      DodamApp(
        activityRepository: const _ActivityRepository(),
        reportRepository: reportRepository,
        initialRoute: AppRoutes.activityDetail('120'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('activity-report-cta')),
    );
    await tester.tap(find.byKey(const ValueKey('activity-report-cta')));
    await tester.pumpAndSettle();

    expect(reportRepository.calls, [777]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('우리 가족'), findsOneWidget);
  });

  testWidgets('완료 리포트의 계약 섹션을 실제 값으로 표시한다', (tester) async {
    final repository = _ReportRepository();
    await _openReport(tester, repository);

    expect(repository.calls, [501]);
    // drawingSession
    expect(find.text('우리 가족'), findsOneWidget);
    expect(find.text('그림일기'), findsOneWidget);
    expect(find.text('CANVAS'), findsOneWidget);
    expect(find.text('23분'), findsOneWidget);
    // childExpression
    expect(find.text('동생이랑 놀아서 좋았어요'), findsOneWidget);
    expect(find.textContaining('우리 동생이야.'), findsOneWidget);
    expect(find.text('기쁨'), findsOneWidget);
    // activityFacts
    expect(find.text('사람, 집'), findsOneWidget);
    // conversationSummary
    expect(find.text('편안하게 대화했어요.'), findsOneWidget);
    // guardianConversationGuide + limitations
    expect(find.text('어떤 부분이 좋아?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('report-non-diagnostic-notice')),
      findsOneWidget,
    );
    expect(find.textContaining('진단이 아닌 관찰 참고 자료'), findsOneWidget);
  });

  testWidgets('보호자 금지 정보와 구형 문구를 노출하지 않는다', (tester) async {
    await _openReport(tester, _ReportRepository());

    expect(find.textContaining('위험도'), findsNothing);
    expect(find.textContaining('진단명'), findsNothing);
    expect(find.text('음성으로 답했어요 · 재생 파일 미제공'), findsNothing);
    // 490 이전이므로 재생 컨트롤은 없다.
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('representativeUtterances가 비면 아이 표현 섹션을 만들지 않는다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(expression: _emptyExpression)),
    );

    expect(find.byKey(const ValueKey('report-child-expression')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('messageId가 null인 발화도 텍스트로 표시한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(
        report: _report(
          expression: const ReportChildExpressionDto(
            selectedEmotions: [],
            expressedEmotionText: null,
            representativeUtterances: [
              ReportUtteranceDto(
                messageId: null,
                text: '원본 없는 음성 답변',
                source: 'STT',
                sttNeedsConfirmation: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('원본 없는 음성 답변'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('조회 중 Loading을 표시한다', (tester) async {
    final pending = Completer<ReportDetailDto>();
    final repository = _ReportRepository(pending: pending);
    await _openReport(tester, repository, settle: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('report-loading')), findsOneWidget);
    pending.complete(_completed);
    await tester.pumpAndSettle();
  });

  testWidgets('GENERATING 상태는 polling 없이 준비 안내를 표시한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(status: 'GENERATING', sections: false)),
      settle: false,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('report-generating')), findsOneWidget);
    expect(find.text('관찰 리포트를 준비하고 있어요'), findsOneWidget);
  });

  testWidgets('FAILED 상태에서 같은 reportId를 다시 조회한다', (tester) async {
    final repository = _ReportRepository(
      report: _report(status: 'FAILED', sections: false),
    );
    await _openReport(tester, repository);
    expect(find.byKey(const ValueKey('report-failed')), findsOneWidget);

    repository.report = _completed;
    await tester.tap(find.text('다시 확인'));
    await tester.pumpAndSettle();
    expect(repository.calls, [501, 501]);
  });

  testWidgets('네트워크 Error에서 Retry할 수 있다', (tester) async {
    final repository = _ReportRepository(
      error: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    );
    await _openReport(tester, repository);
    expect(find.byKey(const ValueKey('report-error')), findsOneWidget);

    repository.error = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(repository.calls, [501, 501]);
  });

  testWidgets('403 권한 오류는 재시도 없이 오류 상태를 보여준다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(
        error: const ApiResponseFailure(
          statusCode: 403,
          error: ApiError(
            code: 'REPORT_ACCESS_DENIED',
            message: '리포트에 접근할 권한이 없습니다.',
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('report-error')), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('invalid reportId는 API를 호출하지 않는다', (tester) async {
    final repository = _ReportRepository();
    await _openReport(tester, repository, reportId: 'invalid');
    expect(repository.calls, isEmpty);
    expect(find.byKey(const ValueKey('report-invalid-id')), findsOneWidget);
  });

  testWidgets('404 REPORT_NOT_FOUND는 Empty로 처리한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(
        error: const ApiResponseFailure(
          statusCode: 404,
          error: ApiError(code: 'REPORT_NOT_FOUND', message: '리포트를 찾을 수 없습니다.'),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('report-empty')), findsOneWidget);
  });

  testWidgets('응답 reportId가 요청과 다르면 Empty로 처리한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(reportId: 777)),
    );
    expect(find.byKey(const ValueKey('report-empty')), findsOneWidget);
  });

  testWidgets('관찰 섹션이 모두 비면 빈 데이터 안내를 아이콘과 함께 표시한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(sections: false)),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('report-no-observations')),
      findsOneWidget,
    );
    expect(find.text('아직 표시할 관찰 기록이 없어요.'), findsOneWidget);
    // 색상 외 신호: 전용 아이콘을 함께 쓴다.
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });

  testWidgets('이미지가 없으면 placeholder를 아이콘과 문구로 표시한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(sections: false)),
    );

    expect(
      find.byKey(const ValueKey('report-image-placeholder')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.text('그림을 불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('Home CTA는 48dp 이상이며 Guardian Home으로 이동한다', (tester) async {
    await _openReport(tester, _ReportRepository());
    final cta = find.byKey(const ValueKey('report-home-cta'));
    await tester.ensureVisible(cta);

    expect(tester.getSize(cta).height, greaterThanOrEqualTo(48));

    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.text('보호자 홈'), findsWidgets);
  });

  testWidgets('loading 상태에 Semantics 라벨을 제공한다', (tester) async {
    final handle = tester.ensureSemantics();
    final pending = Completer<ReportDetailDto>();
    await _openReport(
      tester,
      _ReportRepository(pending: pending),
      settle: false,
    );
    await tester.pump();

    expect(find.bySemanticsLabel('관찰 리포트를 불러오고 있어요'), findsOneWidget);

    pending.complete(_completed);
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('empty 상태에 Semantics 라벨을 제공한다', (tester) async {
    final handle = tester.ensureSemantics();
    await _openReport(
      tester,
      _ReportRepository(
        error: const ApiResponseFailure(
          statusCode: 404,
          error: ApiError(code: 'REPORT_NOT_FOUND', message: '없음'),
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('관찰 리포트를 찾을 수 없어요')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('error 상태에 Semantics 라벨을 제공한다', (tester) async {
    final handle = tester.ensureSemantics();
    await _openReport(
      tester,
      _ReportRepository(
        error: const ApiTransportFailure(
          type: ApiTransportFailureType.connection,
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('관찰 리포트를 불러오지 못했어요')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('textScale 2.0에서도 overflow가 없다', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openReport(tester, _ReportRepository(), textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('우리 가족'), findsOneWidget);
  });

  testWidgets('작은 화면에서도 단일 스크롤로 overflow가 없다', (tester) async {
    tester.view.physicalSize = const Size(500, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openReport(tester, _ReportRepository());

    expect(find.byKey(const ValueKey('report-small-layout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('넓은 화면에서는 2단 레이아웃으로 배치한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openReport(tester, _ReportRepository());

    expect(find.byKey(const ValueKey('report-wide-layout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openReport(
  WidgetTester tester,
  ReportRepository repository, {
  String reportId = '501',
  bool settle = true,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: DodamApp(
        reportRepository: repository,
        initialRoute: AppRoutes.report(reportId),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final class _ReportRepository implements ReportRepository {
  _ReportRepository({ReportDetailDto? report, this.pending, this.error})
    : report = report ?? _completed;

  ReportDetailDto report;
  final Completer<ReportDetailDto>? pending;
  Object? error;
  final List<int> calls = [];

  @override
  Future<ReportDetailDto> getReport(int reportId) async {
    calls.add(reportId);
    if (error case final error?) throw error;
    return pending?.future ?? report;
  }

  @override
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  }) => throw UnimplementedError();

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
  const _ActivityRepository();

  @override
  Future<ActivityDetailDto> getActivity(int activityId) async =>
      ActivityDetailDto(
        activityId: activityId,
        childId: 3,
        title: '우리 가족',
        drawingType: const ActivityDrawingTypeDto(
          code: 'ART_DIARY',
          name: '그림일기',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'COMPLETED',
        currentStage: 'COMPLETED',
        selectedEmotions: const ['JOY'],
        expressedEmotionText: null,
        startedAt: '2026-07-20T09:40:00Z',
        completedAt: '2026-07-20T10:03:00Z',
        assets: const [],
        conversation: null,
        analysis: null,
        report: const ActivityReportSummaryDto(
          reportId: 777,
          reportStatus: 'COMPLETED',
          reportVersion: 1,
        ),
      );

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) => throw UnimplementedError();

  @override
  Future<void> deleteActivity(int activityId) => throw UnimplementedError();
}

const _emptyExpression = ReportChildExpressionDto(
  selectedEmotions: [],
  expressedEmotionText: null,
  representativeUtterances: [],
);

final _completed = _report();

ReportDetailDto _report({
  int reportId = 501,
  String status = 'COMPLETED',
  bool sections = true,
  ReportChildExpressionDto? expression,
}) => ReportDetailDto(
  reportId: reportId,
  reportVersion: 1,
  reportStatus: status,
  drawingSession: sections
      ? const ReportDrawingSessionDto(
          drawingSessionId: 120,
          childId: 3,
          drawingTypeCode: 'ART_DIARY',
          drawingTypeName: '그림일기',
          title: '우리 가족',
          inputMethod: 'CANVAS',
          startedAt: '2026-07-20T09:40:00',
          completedAt: '2026-07-20T10:03:00',
          durationMs: 1380000,
        )
      : null,
  // 위젯 테스트에서 실제 네트워크 이미지를 받지 않도록 URL은 비운다.
  drawing: const ReportDrawingDto(finalImageUrl: null, thumbnailUrl: null),
  childExpression:
      expression ??
      (sections
          ? const ReportChildExpressionDto(
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
            )
          : _emptyExpression),
  activityFacts: sections
      ? const ReportActivityFactsDto(
          detectedObjects: ['사람', '집'],
          drawingDurationMs: 1320000,
          pauseCount: 4,
          eraseCount: 2,
          pressureAvailable: false,
          notes: [],
        )
      : null,
  conversationSummary: sections
      ? const ReportConversationSummaryDto(
          questionCount: 5,
          answeredCount: 4,
          skippedCount: 1,
          summary: '편안하게 대화했어요.',
        )
      : null,
  guardianConversationGuide: sections ? const ['어떤 부분이 좋아?'] : const [],
  limitations: sections ? const ['이 리포트는 진단이 아닌 관찰 참고 자료입니다.'] : const [],
  expertReview: const ReportExpertReviewDto(
    status: 'NOT_REQUESTED',
    available: false,
  ),
  createdAt: '2026-07-20T10:12:00',
);
