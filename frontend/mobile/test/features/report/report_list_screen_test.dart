import 'dart:typed_data';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:dodam/features/report/data/dto/report_dtos.dart';
import 'package:dodam/features/report/domain/repositories/report_repository.dart';
import 'package:dodam/features/report/presentation/screens/report_list_screen.dart';
import 'package:dodam/features/report/presentation/screens/report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 홈에서 '전체 리포트 목록'으로 가는 진입점은 보호자 홈 개편(S15P11B209-690)
  // 이후 두지 않기로 확정했다. 홈이 책임지는 것은 최신 리포트 진입점 하나뿐이다.
  testWidgets('보호자 홈은 최신 리포트로 가는 진입점을 제공한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(
        childRepository: const _ChildRepository(),
        reportRepository: _ReportRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('child-3')));
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey('guardian-latest-report-501'));
    expect(entry, findsOneWidget);
    // 존재만으로는 부족하다 — 실제로 눌러서 넘어갈 수 있어야 한다.
    expect(tester.widget<InkWell>(entry).onTap, isNotNull);

    // 눌렀을 때 "그 리포트 1장의 단일 상세(ReportScreen, id 501)"로 이동해야 한다.
    // 전체 목록(ReportListScreen)이 아니어야 한다.
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ReportScreen>(find.byType(ReportScreen)).reportId,
      '501',
    );
    expect(find.byType(ReportListScreen), findsNothing);
  });

  testWidgets('완료된 리포트가 없으면 최신 리포트 진입점이 비활성이다', (tester) async {
    // 최근 활동에 완료 리포트가 없으면 진입점 key가 아예 없어(진입 불가)
    // "키 존재 = 진입 가능"이 성립하고, 버튼은 눌리지 않는다.
    await tester.pumpWidget(
      DodamApp(
        childRepository: const _ChildRepository(),
        activityRepository: _NoReportActivityRepository(),
        reportRepository: _ReportRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('child-3')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('guardian-latest-report-501')),
      findsNothing,
    );
    final button = find.ancestor(
      of: find.text('최신 리포트 보기'),
      matching: find.byType(InkWell),
    );
    expect(button, findsOneWidget);
    expect(tester.widget<InkWell>(button).onTap, isNull);
  });

  testWidgets('완료·생성 중·실패 리포트를 상태별로 표시한다', (tester) async {
    final controller = GuardianChildController(const _ChildRepository());
    await controller.loadChildren();
    controller.selectChild(controller.children.single);

    await tester.pumpWidget(
      MaterialApp(
        home: ReportListScreen(
          childController: controller,
          repository: _ReportRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('report-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-card-501')), findsOneWidget);
    expect(find.text('리포트 완료'), findsOneWidget);
    expect(find.text('분석 중'), findsOneWidget);
    expect(find.text('다시 확인 필요'), findsOneWidget);
  });

  testWidgets('목록 조회 실패 후 다시 시도할 수 있다', (tester) async {
    final controller = GuardianChildController(const _ChildRepository());
    await controller.loadChildren();
    controller.selectChild(controller.children.single);
    final repository = _ReportRepository(error: StateError('network'));

    await tester.pumpWidget(
      MaterialApp(
        home: ReportListScreen(
          childController: controller,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-list-error')), findsOneWidget);

    repository.error = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(find.byKey(const ValueKey('report-list')), findsOneWidget);
  });

  test('REPORT-01 최신 목록 계약을 파싱한다', () {
    final report = ReportSummaryDto.fromJson(const {
      'reportId': 501,
      'reportVersion': 2,
      'drawingSessionId': 120,
      'drawingType': {'drawingTypeId': 7, 'code': 'ART_DIARY', 'name': '그림 일기'},
      'title': '오늘의 그림',
      'thumbnailUrl': '/api/v1/drawing-assets/30/file',
      'activityDate': '2026-07-22',
      'durationMs': 300000,
      'selectedEmotions': ['HAPPY'],
      'reportStatus': 'COMPLETED',
      'expertReviewAvailable': false,
    });

    expect(report.drawingTypeCode, 'ART_DIARY');
    expect(report.activityDate, DateTime(2026, 7, 22));
    expect(report.durationMs, 300000);
    expect(report.expertReviewAvailable, isFalse);
  });
}

final class _ReportRepository implements ReportRepository {
  _ReportRepository({this.error});

  Object? error;
  int calls = 0;

  @override
  Future<ReportGenerationStatusDto> getGenerationStatus(int reportId) =>
      throw UnimplementedError();

  @override
  Future<ReportGenerationStatusDto> regenerateReport(
    int reportId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadImage(String imageUrl) =>
      throw UnimplementedError();

  @override
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  }) async {
    calls += 1;
    if (error case final error?) throw error;
    return ApiPage(
      content: const [
        ReportSummaryDto(
          reportId: 501,
          drawingSessionId: 120,
          reportVersion: 1,
          reportStatus: 'COMPLETED',
          title: '우리 가족',
          drawingTypeId: 7,
          drawingTypeCode: 'ART_DIARY',
          drawingTypeName: '그림 일기',
          selectedEmotions: ['HAPPY'],
          thumbnailUrl: null,
          activityDate: null,
          durationMs: 300000,
          expertReviewAvailable: false,
        ),
        ReportSummaryDto(
          reportId: 502,
          drawingSessionId: 121,
          reportVersion: 1,
          reportStatus: 'GENERATING',
          title: '나무 그림',
          drawingTypeId: 8,
          drawingTypeCode: 'HTP_TREE',
          drawingTypeName: 'HTP 검사',
          selectedEmotions: [],
          thumbnailUrl: null,
          activityDate: null,
          durationMs: null,
          expertReviewAvailable: false,
        ),
        ReportSummaryDto(
          reportId: 503,
          drawingSessionId: 122,
          reportVersion: 1,
          reportStatus: 'FAILED',
          title: '집 그림',
          drawingTypeId: 9,
          drawingTypeCode: 'HTP_HOUSE',
          drawingTypeName: 'HTP 검사',
          selectedEmotions: [],
          thumbnailUrl: null,
          activityDate: null,
          durationMs: null,
          expertReviewAvailable: false,
        ),
      ],
      page: 0,
      size: 20,
      totalElements: 3,
      totalPages: 1,
      hasNext: false,
    );
  }

  @override
  Future<ReportDetailDto> getReport(int reportId) => throw UnimplementedError();

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
  Future<AnalysisRetryResponseDto> retryAnalysis(
    int analysisId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

/// 최근 활동은 있지만 완료 리포트가 없는 상태(진입점 비활성 검증용).
final class _NoReportActivityRepository implements ActivityRepository {
  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async => ApiPage(
    content: const [
      ActivitySummaryDto(
        activityId: 120,
        title: '우리 가족',
        drawingType: ActivityDrawingTypeDto(code: 'ART_DIARY', name: '그림일기'),
        inputMethod: 'CANVAS',
        sessionStatus: 'COMPLETED',
        selectedEmotions: ['HAPPY'],
        thumbnailUrl: null,
        analysisStatus: 'COMPLETED',
        report: null,
        startedAt: '2026-07-20T09:40:00Z',
        completedAt: '2026-07-20T10:03:00Z',
      ),
    ],
    page: 0,
    size: 20,
    totalElements: 1,
    totalPages: 1,
    hasNext: false,
  );

  @override
  Future<void> deleteActivity(int activityId) async {}

  @override
  Future<ActivityDetailDto> getActivity(int activityId) =>
      throw UnimplementedError();

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadImage(String url) => throw UnimplementedError();
}

final class _ChildRepository implements ChildRepository {
  const _ChildRepository();

  @override
  Future<List<ChildSummaryDto>> getChildren() async => const [_child];

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) =>
      throw UnimplementedError();

  @override
  Future<void> deleteChild(int childId) => throw UnimplementedError();

  @override
  Future<ChildDetailDto> getChild(int childId) => throw UnimplementedError();

  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) =>
      throw UnimplementedError();

  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) => throw UnimplementedError();
}

const _child = ChildSummaryDto(
  childId: 3,
  nickname: '도담이',
  birthDate: '2020-01-01',
  age: 6,
  profileImageUrl: null,
  preferredCharacter: null,
  questionDifficulty: 'EASY',
  tutorialStatus: 'COMPLETED',
  relationshipType: 'PARENT',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: '2026-07-22T04:00:00Z',
    totalActivityCount: 3,
  ),
);
