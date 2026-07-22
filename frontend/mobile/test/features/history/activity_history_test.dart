import 'dart:async';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:dodam/features/history/presentation/screens/history_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Guardian Home에서 선택 아동의 Activity History로 진입한다', (tester) async {
    final repository = _ActivityRepository();
    await _openHistory(tester, repository);

    expect(repository.calls, 1);
    expect(repository.lastChildId, 3);
    expect(find.text('활동 이력'), findsWidgets);
    expect(find.byKey(const ValueKey('activity-120')), findsOneWidget);
    expect(find.text('우리 가족'), findsWidgets);
    expect(
      find.byKey(const ValueKey('activity-history-summary')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('activity-121')));
    await tester.pump();
    expect(find.text('비 오는 날'), findsWidgets);
    final selectedCard = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey('activity-121')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(selectedCard.properties.selected, isTrue);

    await tester.ensureVisible(
      find.byKey(const ValueKey('activity-detail-cta')),
    );
    await tester.tap(find.byKey(const ValueKey('activity-detail-cta')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ActivityDetailScreen>(find.byType(ActivityDetailScreen))
          .activityId,
      '121',
    );
  });

  testWidgets('목록 Loading 상태를 표시한다', (tester) async {
    final pending = Completer<ApiPage<ActivitySummaryDto>>();
    final repository = _ActivityRepository(pending: pending);
    await _openHistory(tester, repository, settleAfterNavigation: false);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('activity-history-loading')),
      findsOneWidget,
    );
    pending.complete(_page(_activities));
    await tester.pumpAndSettle();
  });

  testWidgets('목록 Empty 상태를 표시한다', (tester) async {
    await _openHistory(tester, _ActivityRepository(activities: const []));
    expect(
      find.byKey(const ValueKey('activity-history-empty')),
      findsOneWidget,
    );
  });

  testWidgets('목록 Error에서 Retry할 수 있다', (tester) async {
    final repository = _ActivityRepository(error: StateError('network'));
    await _openHistory(tester, repository);
    expect(
      find.byKey(const ValueKey('activity-history-error')),
      findsOneWidget,
    );

    repository.error = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.byKey(const ValueKey('activity-history-list')), findsOneWidget);
  });

  testWidgets('지원되는 기간과 Drawing Type 필터만 Repository에 전달한다', (tester) async {
    final repository = _ActivityRepository();
    await _openHistory(tester, repository);

    await tester.tap(find.text('전체 기간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('최근 30일').last);
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(repository.lastFilter?.from, isNotNull);
    expect(repository.lastFilter?.to, isNotNull);

    await tester.tap(find.text('전체 활동'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('자유화').last);
    await tester.pumpAndSettle();
    expect(repository.calls, 3);
    expect(repository.lastFilter?.drawingType, 'FREE_DRAWING');
  });

  testWidgets('선택된 childId가 없으면 가짜 조회 없이 안내한다', (tester) async {
    final repository = _ActivityRepository();
    await tester.pumpWidget(
      DodamApp(
        childRepository: const _ChildRepository(),
        activityRepository: repository,
        initialRoute: AppRoutes.activityHistory,
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.calls, 0);
    expect(
      find.byKey(const ValueKey('activity-history-no-child')),
      findsOneWidget,
    );
  });

  testWidgets('thumbnail 실패와 작은 화면에서도 목록과 요약을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(600, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openHistory(tester, _ActivityRepository());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('activity-history-small-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-thumbnail-placeholder')),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('activity-history-list')), findsOneWidget);
  });

  testWidgets('뒤로가기는 Guardian Home으로 복귀한다', (tester) async {
    await _openHistory(tester, _ActivityRepository());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('보호자 홈'), findsWidgets);
  });
}

Future<void> _openHistory(
  WidgetTester tester,
  ActivityRepository repository, {
  bool settleAfterNavigation = true,
}) async {
  await tester.pumpWidget(
    DodamApp(
      childRepository: const _ChildRepository(),
      activityRepository: repository,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('child-3')));
  await tester.pump();
  final entry = find.byKey(const ValueKey('activity-history-entry'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  if (settleAfterNavigation) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final class _ActivityRepository implements ActivityRepository {
  _ActivityRepository({
    List<ActivitySummaryDto>? activities,
    this.error,
    this.pending,
  }) : activities = activities ?? _activities;

  List<ActivitySummaryDto> activities;
  Object? error;
  final Completer<ApiPage<ActivitySummaryDto>>? pending;
  int calls = 0;
  int? lastChildId;
  ActivityFilterDto? lastFilter;

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async {
    calls += 1;
    lastChildId = childId;
    lastFilter = filter;
    if (error case final error?) throw error;
    return pending?.future ?? _page(activities);
  }

  @override
  Future<void> deleteActivity(int activityId) async {}

  @override
  Future<ActivityDetailDto> getActivity(int activityId) =>
      throw UnimplementedError();
}

ApiPage<ActivitySummaryDto> _page(List<ActivitySummaryDto> activities) =>
    ApiPage(
      content: activities,
      page: 0,
      size: 20,
      totalElements: activities.length,
      totalPages: activities.isEmpty ? 0 : 1,
      hasNext: false,
    );

final _activities = [
  _activity(120, '우리 가족', 'ART_DIARY', '그림일기'),
  _activity(121, '비 오는 날', 'FREE_DRAWING', '자유화'),
];

ActivitySummaryDto _activity(int id, String title, String code, String name) =>
    ActivitySummaryDto(
      activityId: id,
      title: title,
      drawingType: ActivityDrawingTypeDto(code: code, name: name),
      inputMethod: 'CANVAS',
      sessionStatus: 'COMPLETED',
      selectedEmotions: const ['HAPPY'],
      thumbnailUrl: 'https://invalid.example/$id.png',
      analysisStatus: 'COMPLETED',
      report: null,
      startedAt: '2026-07-20T09:40:00Z',
      completedAt: '2026-07-20T10:03:00Z',
    );

final class _ChildRepository implements ChildRepository {
  const _ChildRepository();
  @override
  Future<List<ChildSummaryDto>> getChildren() async => const [_child];
  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) =>
      throw UnimplementedError();
  @override
  Future<void> deleteChild(int childId, {bool cascade = true}) =>
      throw UnimplementedError();
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
  birthDate: '2019-03-14',
  age: 7,
  profileImageUrl: null,
  preferredCharacter: 'BEAR',
  questionDifficulty: 'PRESCHOOL',
  tutorialStatus: 'COMPLETED',
  relationshipType: 'MOTHER',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: '2026-07-20T08:15:00Z',
    totalActivityCount: 2,
  ),
);
