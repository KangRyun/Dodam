import 'dart:async';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/report/data/dto/report_dtos.dart';
import 'package:dodam/features/report/domain/repositories/report_repository.dart';
import 'package:dodam/features/report/presentation/screens/report_screen.dart';
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

  testWidgets('실제 reportId로 조회하고 완료 리포트의 DTO 필드를 표시한다', (tester) async {
    final repository = _ReportRepository();
    await _openReport(tester, repository);

    expect(repository.calls, [501]);
    expect(find.text('우리 가족'), findsOneWidget);
    expect(find.text('가족을 화면 가운데에 크게 그렸어요'), findsOneWidget);
    expect(find.text('Q. 이 사람은 누구야?'), findsOneWidget);
    expect(find.text('A. 우리 동생이야.'), findsOneWidget);
    expect(find.text('아이가 선택한 감정'), findsOneWidget);
    expect(find.text('기쁨'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('report-non-diagnostic-notice')),
      findsOneWidget,
    );
    expect(find.textContaining('진단이 아닌 관찰 참고 자료'), findsOneWidget);
    expect(find.textContaining('위험도'), findsNothing);
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
    final repository = _ReportRepository(error: StateError('network'));
    await _openReport(tester, repository);
    expect(find.byKey(const ValueKey('report-error')), findsOneWidget);

    repository.error = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(repository.calls, [501, 501]);
  });

  testWidgets('invalid reportId는 API를 호출하지 않는다', (tester) async {
    final repository = _ReportRepository();
    await _openReport(tester, repository, reportId: 'invalid');
    expect(repository.calls, isEmpty);
    expect(find.byKey(const ValueKey('report-invalid-id')), findsOneWidget);
  });

  testWidgets('404와 응답 ID 불일치는 Empty로 처리한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(
        error: const ApiResponseFailure(statusCode: 404, error: null),
      ),
    );
    expect(find.byKey(const ValueKey('report-empty')), findsOneWidget);

    await _openReport(
      tester,
      _ReportRepository(report: _report(reportId: 777)),
    );
    expect(find.byKey(const ValueKey('report-empty')), findsOneWidget);
  });

  testWidgets('nullable section과 이미지 부재에도 화면을 유지한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(sections: false, imageUrl: null)),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('report-image-placeholder')),
      findsOneWidget,
    );
    expect(find.text('아직 표시할 관찰 기록이 없어요.'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('이미지 URL 로딩 실패 시 placeholder를 표시한다', (tester) async {
    await _openReport(tester, _ReportRepository());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('report-image-placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('Home CTA는 Guardian Home으로 이동한다', (tester) async {
    await _openReport(tester, _ReportRepository());
    await tester.ensureVisible(find.byKey(const ValueKey('report-home-cta')));
    await tester.tap(find.byKey(const ValueKey('report-home-cta')));
    await tester.pumpAndSettle();
    expect(find.text('보호자 홈'), findsWidgets);
  });

  testWidgets('Back은 이전 Activity Detail 화면으로 복귀한다', (tester) async {
    final repository = _ReportRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ReportScreen(reportId: '501', repository: repository),
                ),
              ),
              child: const Text('Activity Detail'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Activity Detail'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Activity Detail'), findsOneWidget);
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
}

Future<void> _openReport(
  WidgetTester tester,
  ReportRepository repository, {
  String reportId = '501',
  bool settle = true,
}) async {
  await tester.pumpWidget(
    DodamApp(
      reportRepository: repository,
      initialRoute: AppRoutes.report(reportId),
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

final _completed = _report();

ReportDetailDto _report({
  int reportId = 501,
  String status = 'COMPLETED',
  bool sections = true,
  String? imageUrl = 'https://invalid.example/report.png',
}) => ReportDetailDto(
  reportId: reportId,
  drawingSessionId: 120,
  analysisId: 88,
  reportVersion: 1,
  reportStatus: status,
  activitySummary: sections
      ? const ReportActivitySummaryDto(
          title: '우리 가족',
          drawingType: {'code': 'ART_DIARY', 'name': '그림일기'},
          inputMethod: 'CANVAS',
          startedAt: '2026-07-20T09:40:00Z',
          completedAt: '2026-07-20T10:03:00Z',
          durationMinutes: 23,
          selectedEmotions: ['JOY'],
        )
      : null,
  drawingImageUrl: imageUrl,
  observedFeatures: sections
      ? const [
          ObservedFeatureDto(
            label: '가족을 화면 가운데에 크게 그렸어요',
            description: '따뜻한 색을 주로 사용했어요.',
            evidenceRef: 'OBJ_PERSON_1',
          ),
        ]
      : null,
  keyConversations: sections
      ? const [
          KeyConversationDto(
            question: '이 사람은 누구야?',
            answer: '우리 동생이야.',
            answerType: 'VOICE',
          ),
        ]
      : null,
  evidence: null,
  followUp: sections
      ? const ReportFollowUpDto(
          attentionPoints: ['함께 확인해 주세요.'],
          guidance: '열린 질문으로 대화해 보세요.',
        )
      : null,
  guardianQuestions: sections ? const ['어떤 부분이 좋아?'] : null,
  isExpertReviewRecommended: sections ? false : null,
  limitationsText: '이 리포트는 진단이 아닌 관찰 참고 자료입니다.',
  modelVersion: sections ? 'dodam-report-v1.2' : null,
  createdAt: '2026-07-20T10:12:00Z',
);
