import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('실제 activityId로 상세를 조회하고 DTO 필드를 표시한다', (tester) async {
    final repository = _DetailRepository();
    await _openDetail(tester, repository);

    expect(repository.detailCalls, [120]);
    expect(find.text('우리 가족'), findsOneWidget);
    expect(find.text('그림일기'), findsWidgets);
    expect(find.text('기쁨'), findsOneWidget);
    expect(find.textContaining('동생이랑 놀아서 좋았어'), findsOneWidget);
    expect(find.text('6개'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-detail-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-report-cta')), findsOneWidget);
    expect(find.text('엄마와 아빠는 어디 있어?'), findsNothing);
  });

  testWidgets('상세 조회 중 Loading을 표시한다', (tester) async {
    final pending = Completer<ActivityDetailDto>();
    final repository = _DetailRepository(pending: pending);
    await _openDetail(tester, repository, settle: false);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('activity-detail-loading')),
      findsOneWidget,
    );
    pending.complete(_detail);
    await tester.pumpAndSettle();
  });

  testWidgets('조회 실패 후 Retry할 수 있다', (tester) async {
    final repository = _DetailRepository(error: StateError('network'));
    await _openDetail(tester, repository);
    expect(find.byKey(const ValueKey('activity-detail-error')), findsOneWidget);

    repository.error = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(repository.detailCalls, [120, 120]);
    expect(find.text('우리 가족'), findsOneWidget);
  });

  testWidgets('잘못된 activityId는 조회하지 않고 안전하게 안내한다', (tester) async {
    final repository = _DetailRepository();
    await _openDetail(tester, repository, activityId: 'invalid');

    expect(repository.detailCalls, isEmpty);
    expect(
      find.byKey(const ValueKey('activity-detail-invalid-id')),
      findsOneWidget,
    );
  });

  testWidgets('응답 ID가 다르면 가짜 상세 대신 Empty를 표시한다', (tester) async {
    final repository = _DetailRepository(detail: _detailWith(activityId: 121));
    await _openDetail(tester, repository);
    expect(find.byKey(const ValueKey('activity-detail-empty')), findsOneWidget);
  });

  testWidgets('이미지 실패와 nullable 데이터에도 화면을 유지한다', (tester) async {
    final repository = _DetailRepository(
      detail: _detailWith(
        title: null,
        selectedEmotions: const [],
        expressedEmotionText: null,
        conversation: null,
        analysis: null,
        report: null,
      ),
    );
    await _openDetail(tester, repository);
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('activity-detail-image-placeholder')),
      findsOneWidget,
    );
    expect(find.text('선택한 감정 정보가 없어요.'), findsOneWidget);
    expect(find.text('이 활동에서 제공된 대화 정보가 없어요.'), findsOneWidget);
    expect(find.text('아직 생성된 요약이 없어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-report-cta')), findsNothing);
  });

  testWidgets('실제 reportId가 있을 때만 Report route로 이동한다', (tester) async {
    await _openDetail(tester, _DetailRepository());
    await tester.ensureVisible(
      find.byKey(const ValueKey('activity-report-cta')),
    );
    await tester.tap(find.byKey(const ValueKey('activity-report-cta')));
    await tester.pumpAndSettle();

    expect(find.text('관찰 리포트'), findsWidgets);
  });

  testWidgets('작은 화면은 단일 스크롤로 overflow 없이 표시한다', (tester) async {
    tester.view.physicalSize = const Size(500, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDetail(tester, _DetailRepository());
    expect(
      find.byKey(const ValueKey('activity-detail-small-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openDetail(
  WidgetTester tester,
  ActivityRepository repository, {
  String activityId = '120',
  bool settle = true,
}) async {
  await tester.pumpWidget(
    DodamApp(
      activityRepository: repository,
      initialRoute: AppRoutes.activityDetail(activityId),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final class _DetailRepository implements ActivityRepository {
  _DetailRepository({ActivityDetailDto? detail, this.pending, this.error})
    : detail = detail ?? _detail;

  ActivityDetailDto detail;
  final Completer<ActivityDetailDto>? pending;
  Object? error;
  final List<int> detailCalls = [];

  @override
  Future<ActivityDetailDto> getActivity(int activityId) async {
    detailCalls.add(activityId);
    if (error case final error?) throw error;
    return pending?.future ?? detail;
  }

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) => throw UnimplementedError();

  @override
  Future<void> deleteActivity(int activityId) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadImage(String url) =>
      throw StateError('image fetch failed');
}

const _asset = ActivityAssetDto(
  assetId: 900,
  assetType: 'FINAL',
  assetVersion: 2,
  fileUrl: 'https://invalid.example/final.png',
  mimeType: 'image/png',
  widthPx: 1600,
  heightPx: 1000,
);

const _conversation = ActivityConversationSummaryDto(
  conversationSessionId: 77,
  conversationStatus: 'COMPLETED',
  questionCount: 6,
  completedAt: '2026-07-20T10:01:00Z',
);

const _analysis = ActivityAnalysisSummaryDto(
  analysisId: 88,
  analysisStatus: 'COMPLETED',
  completedAt: '2026-07-20T10:11:00Z',
);

const _report = ActivityReportSummaryDto(
  reportId: 501,
  reportStatus: 'COMPLETED',
  reportVersion: 1,
);

final _detail = _detailWith();

ActivityDetailDto _detailWith({
  int activityId = 120,
  String? title = '우리 가족',
  List<String> selectedEmotions = const ['HAPPY'],
  String? expressedEmotionText = '동생이랑 놀아서 좋았어',
  ActivityConversationSummaryDto? conversation = _conversation,
  ActivityAnalysisSummaryDto? analysis = _analysis,
  ActivityReportSummaryDto? report = _report,
}) => ActivityDetailDto(
  activityId: activityId,
  childId: 3,
  title: title,
  drawingType: const ActivityDrawingTypeDto(code: 'ART_DIARY', name: '그림일기'),
  inputMethod: 'CANVAS',
  sessionStatus: 'COMPLETED',
  currentStage: 'COMPLETED',
  selectedEmotions: selectedEmotions,
  expressedEmotionText: expressedEmotionText,
  startedAt: '2026-07-20T09:40:00Z',
  completedAt: '2026-07-20T10:03:00Z',
  assets: const [_asset],
  conversation: conversation,
  analysis: analysis,
  report: report,
);
