import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/app/widgets/guardian_sidebar_shell.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:dodam/features/guardian/presentation/widgets/guardian_dashboard.dart';
import 'package:dodam/features/guardian/presentation/screens/guardian_screens.dart';
import 'package:dodam/features/notification/application/push_registration_status_controller.dart';
import 'package:dodam/features/notification/domain/failures/push_token_registration_failure.dart';
import 'package:dodam/features/notification/presentation/widgets/push_registration_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 보호자 홈 최근 활동 Bottom Overflow(S15P11B209-848).
///
/// 마음카드가 압축되지 않아 남은 높이를 최근 활동 카드가 모두 흡수하면 카드 내부
/// RenderFlex가 넘쳤다. 화면 크기·글자 배율·배너·최근 활동 상태를 조합해 production
/// [GuardianDashboard]에서 overflow가 없고 CTA와 최근 활동에 실제로 닿을 수 있는지
/// 확인한다.
void main() {
  group('production 보호자 shell', () {
    testWidgets('Pixel Tablet 실제 viewport와 6개 아이·S842 배너에서 overflow가 없다', (
      tester,
    ) async {
      final status = _failedPushStatus();
      addTearDown(status.dispose);
      final routes = <String>[];

      await _pumpProductionDashboard(
        tester,
        physicalSize: const Size(2560, 1600),
        devicePixelRatio: 2,
        physicalPadding: const FakeViewPadding(top: 48, bottom: 64),
        activities: _many(3),
        pushRegistrationStatus: status,
        children: [
          _child(id: 1, nickname: 'minjae'),
          _child(id: 2, nickname: 'donmi'),
          _child(id: 3, nickname: 'asdqwe'),
          _child(id: 4, nickname: 'zzzzz'),
          _child(id: 5, nickname: 'nnew'),
          _child(id: 6, nickname: 'myname'),
        ],
        onPushRoute: routes.add,
      );

      final shell = tester.element(find.byType(GuardianSidebarShell));
      expect(MediaQuery.sizeOf(shell), const Size(1280, 800));
      expect(
        MediaQuery.paddingOf(shell),
        const EdgeInsets.only(top: 24, bottom: 32),
      );
      _expectNoOverflow(tester);
      expect(find.text('최근 활동'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('recent-activity-card')))
            .height,
        greaterThanOrEqualTo(160),
      );

      final entry = find.byKey(const ValueKey('activity-history-entry'));
      expect(entry, findsOneWidget);
      expect(tester.getSize(entry).height, greaterThanOrEqualTo(48));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(routes, ['/guardian/activities']);
      _expectNoOverflow(tester);
    });
  });

  group('화면 크기별 overflow', () {
    for (final layout in _layouts) {
      testWidgets('${layout.label}에서 overflow가 없고 주요 영역에 닿는다', (tester) async {
        final routes = <String>[];
        await _pumpDashboard(
          tester,
          size: layout.size,
          activities: _many(6),
          onPushRoute: routes.add,
        );

        _expectNoOverflow(tester);
        await _expectReachable(tester);
        await _tapActivityHistory(tester, routes);
      });
    }

    testWidgets('글자 배율 2.0에서도 overflow가 없다', (tester) async {
      final routes = <String>[];
      await _pumpDashboard(
        tester,
        size: const Size(1280, 800),
        textScale: 2,
        activities: _many(6),
        onPushRoute: routes.add,
      );

      _expectNoOverflow(tester);
      await _expectReachable(tester);
      await _tapActivityHistory(tester, routes);
    });

    testWidgets('낮은 높이 + 글자 배율 2.0 + 푸시 배너를 함께 겪어도 overflow가 없다', (
      tester,
    ) async {
      final status = _failedPushStatus();
      addTearDown(status.dispose);
      final routes = <String>[];

      await _pumpDashboard(
        tester,
        size: const Size(1280, 360),
        textScale: 2,
        activities: _many(6),
        pushRegistrationStatus: status,
        onPushRoute: routes.add,
      );

      _expectNoOverflow(tester);
      expect(find.byType(PushRegistrationNotice), findsOneWidget);
      await _expectReachable(tester);
      await _tapActivityHistory(tester, routes);
    });

    testWidgets('긴 보호자·아이 이름이 줄바꿈돼도 overflow가 없다', (tester) async {
      await _pumpDashboard(
        tester,
        size: const Size(390, 844),
        nickname: '아주아주긴이름을가진우리집막내도담이어린이',
        activities: _many(6),
      );

      _expectNoOverflow(tester);
      await _expectReachable(tester);
    });
  });

  group('푸시 등록 배너', () {
    testWidgets('배너가 떠도 overflow 없이 배너·CTA가 모두 보인다', (tester) async {
      final status = _failedPushStatus();
      addTearDown(status.dispose);

      await _pumpDashboard(
        tester,
        size: const Size(1280, 800),
        activities: _many(3),
        pushRegistrationStatus: status,
      );

      _expectNoOverflow(tester);
      expect(find.byType(PushRegistrationNotice), findsOneWidget);
      await _expectReachable(tester);
    });

    testWidgets('휴대폰 가로에서 배너가 떠도 overflow가 없다', (tester) async {
      final status = _failedPushStatus();
      addTearDown(status.dispose);

      await _pumpDashboard(
        tester,
        size: const Size(844, 390),
        activities: _many(3),
        pushRegistrationStatus: status,
      );

      _expectNoOverflow(tester);
      await _expectReachable(tester);
    });
  });

  group('최근 활동 상태', () {
    testWidgets('불러오는 중에도 overflow가 없다', (tester) async {
      final pending = Completer<ApiPage<ActivitySummaryDto>>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(_page(const []));
      });

      await _pumpDashboard(
        tester,
        size: const Size(1280, 360),
        activitiesGate: pending,
        settle: false,
      );

      _expectNoOverflow(tester);
      expect(find.text('아직 활동 기록이 없어요.'), findsNothing);
      await _expectRecentHeader(tester);
    });

    testWidgets('활동이 없으면 안내 문구를 보여주고 overflow가 없다', (tester) async {
      await _pumpDashboard(
        tester,
        size: const Size(1280, 360),
        activities: const [],
      );

      _expectNoOverflow(tester);
      await _expectRecentHeader(tester);
      await _expectTextVisible(tester, '아직 활동 기록이 없어요.');
    });

    testWidgets('조회가 실패하면 오류 문구를 보여주고 overflow가 없다', (tester) async {
      await _pumpDashboard(
        tester,
        size: const Size(1280, 360),
        activitiesError: StateError('activity load failed'),
      );

      _expectNoOverflow(tester);
      await _expectRecentHeader(tester);
      await _expectTextVisible(tester, '활동을 불러오지 못했어요.');
    });

    testWidgets('최근 활동 1건을 온전히 표시하고 overflow가 없다', (tester) async {
      await _pumpDashboard(
        tester,
        size: const Size(1280, 800),
        activities: _many(1),
      );

      _expectNoOverflow(tester);
      await _expectRecentHeader(tester);
      expect(find.text('활동 1'), findsOneWidget);
    });

    testWidgets('활동이 있으면 목록을 보여주고 overflow가 없다', (tester) async {
      await _pumpDashboard(
        tester,
        size: const Size(1280, 800),
        activities: _many(3),
      );

      _expectNoOverflow(tester);
      await _expectRecentHeader(tester);
      expect(find.text('활동 1'), findsOneWidget);
    });

    testWidgets('항목이 많아도 카드 안에서만 스크롤하고 overflow가 없다', (tester) async {
      await _pumpDashboard(
        tester,
        size: const Size(1280, 800),
        activities: _many(20),
      );

      _expectNoOverflow(tester);
      await _expectRecentHeader(tester);
      // 최근 활동 목록은 기존대로 카드 안에서 스크롤한다.
      final list = find.descendant(
        of: find.byKey(const ValueKey('activity-history-entry')),
        matching: find.byType(ListView),
      );
      expect(list, findsNothing);
      final cardList = find.byType(ListView);
      expect(cardList, findsOneWidget);
      await tester.drag(cardList, const Offset(0, -200));
      await tester.pumpAndSettle();
      _expectNoOverflow(tester);
    });
  });

  group('스크롤·navigation 회귀', () {
    testWidgets('낮은 높이에서 스크롤해 최근 활동 진입을 실제로 탭한다', (tester) async {
      final routes = <String>[];
      await _pumpDashboard(
        tester,
        size: const Size(1280, 360),
        activities: _many(4),
        onPushRoute: routes.add,
      );

      final entry = find.byKey(const ValueKey('activity-history-entry'));
      await _reveal(tester, entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(routes, ['/guardian/activities']);
      _expectNoOverflow(tester);
    });

    testWidgets('낮은 높이에서 스크롤해 최신 리포트 버튼을 실제로 탭한다', (tester) async {
      final routes = <String>[];
      await _pumpDashboard(
        tester,
        size: const Size(390, 844),
        activities: _many(4),
        onPushRoute: routes.add,
      );

      final report = find.byKey(const ValueKey('guardian-latest-report-11'));
      await _reveal(tester, report);
      await tester.tap(report);
      await tester.pumpAndSettle();

      expect(routes, ['/guardian/reports/11']);
      _expectNoOverflow(tester);
    });

    testWidgets('HTP 활동 버튼은 소개 팝업을 그대로 열고 system back으로 닫힌다', (tester) async {
      await _pumpDashboard(
        tester,
        size: const Size(1280, 360),
        activities: _many(4),
      );

      final cta = find.byKey(const ValueKey('start-child-mode'));
      await _reveal(tester, cta);
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.text('시작하기'), findsOneWidget);

      final state = tester.state<State<StatefulWidget>>(
        find.byType(WidgetsApp),
      );
      // ignore: avoid_dynamic_calls
      await (state as dynamic).didPopRoute();
      await tester.pumpAndSettle();

      expect(find.text('시작하기'), findsNothing);
      _expectNoOverflow(tester);
    });

    testWidgets('아이 전환 칩은 기존대로 선택 상태를 바꾼다', (tester) async {
      final controller = await _pumpDashboard(
        tester,
        size: const Size(1280, 800),
        activities: _many(3),
        children: [
          _child(id: 3, nickname: '하늘'),
          _child(id: 7, nickname: '바다'),
        ],
      );
      expect(controller.selectedChildId, 3);

      final chip = find.byKey(const ValueKey('child-7'));
      await _reveal(tester, chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(controller.selectedChildId, 7);
      _expectNoOverflow(tester);
    });
  });

  group('dispose 안전성', () {
    testWidgets('조회 응답 전에 화면이 사라져도 예외가 없다', (tester) async {
      final pending = Completer<ApiPage<ActivitySummaryDto>>();

      await _pumpDashboard(
        tester,
        size: const Size(1280, 800),
        activitiesGate: pending,
        settle: false,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(_page(_many(3)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

typedef _Layout = ({String label, Size size});

const _layouts = <_Layout>[
  (label: '소형 휴대폰 320×640', size: Size(320, 640)),
  (label: '기존 1280×800', size: Size(1280, 800)),
  (label: '낮은 높이 1280×360', size: Size(1280, 360)),
  (label: '휴대폰 세로 390×844', size: Size(390, 844)),
  (label: '휴대폰 가로 844×390', size: Size(844, 390)),
  (label: '태블릿 세로 800×1280', size: Size(800, 1280)),
  (label: 'Pixel Tablet 가로 1600×1000', size: Size(1600, 1000)),
  // 태블릿 가로 폭 범위 양끝(S15P11B209-787): ResponsiveContent 상한 도입 뒤에도
  // 최소·최대 폭에서 overflow가 없고 본문에 닿을 수 있어야 한다.
  (label: '태블릿 최소 폭 600×900', size: Size(600, 900)),
  (label: '태블릿 최대 폭 1400×900', size: Size(1400, 900)),
];

void _expectNoOverflow(WidgetTester tester) {
  // RenderFlex overflow는 paint 단계에서 보고되므로 예외로 잡힌다.
  expect(tester.takeException(), isNull);
}

/// CTA와 최근 활동 영역이 화면에서 실제로 닿을 수 있는지 본다.
///
/// 존재만 확인하면 Clip으로 가려도 통과하므로 실제로 스크롤해 화면에 올린 뒤
/// 크기를 확인한다.
Future<void> _expectReachable(WidgetTester tester) async {
  await _expectRecentHeader(tester);
  for (final target in [
    find.byKey(const ValueKey('start-child-mode')),
    find.byKey(const ValueKey('activity-history-entry')),
    find.text('기록 없음'),
  ]) {
    await _reveal(tester, target);
    expect(tester.getSize(target).height, greaterThan(0));
  }
  _expectNoOverflow(tester);
}

Future<void> _expectRecentHeader(WidgetTester tester) async {
  final entry = find.byKey(const ValueKey('activity-history-entry'));
  await _reveal(tester, entry);
  expect(find.text('최근 활동'), findsOneWidget);
  expect(tester.getSize(entry).width, greaterThanOrEqualTo(48));
  expect(tester.getSize(entry).height, greaterThanOrEqualTo(48));
  _expectNoOverflow(tester);
}

Future<void> _tapActivityHistory(
  WidgetTester tester,
  List<String> routes,
) async {
  final entry = find.byKey(const ValueKey('activity-history-entry'));
  await _reveal(tester, entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(routes, ['/guardian/activities']);
  _expectNoOverflow(tester);
}

Future<void> _expectTextVisible(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await _reveal(tester, finder);
  expect(tester.getSize(finder).height, greaterThan(0));
  _expectNoOverflow(tester);
}

/// [target]을 화면에 실제로 드러낸다.
///
/// 헤더가 viewport와 cacheExtent를 넘길 만큼 커지면 본문 sliver가 아직 build되지
/// 않아 `find`가 0건이 된다. 그때는 사용자와 같은 방식으로 스크롤해서 올린다.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('child-list-success')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<GuardianChildController> _pumpDashboard(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  List<ActivitySummaryDto>? activities,
  Completer<ApiPage<ActivitySummaryDto>>? activitiesGate,
  Object? activitiesError,
  PushRegistrationStatusController? pushRegistrationStatus,
  String nickname = '도담이',
  List<ChildSummaryDto>? children,
  ValueChanged<String>? onPushRoute,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final childList = children ?? [_child(id: 3, nickname: nickname)];
  final controller = GuardianChildController(_ChildRepository(childList));
  addTearDown(controller.dispose);
  await controller.loadChildren();

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        onGenerateRoute: (settings) {
          final name = settings.name;
          if (name != null && name != '/') onPushRoute?.call(name);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => name == null || name == '/'
                ? Scaffold(
                    body: GuardianDashboard(
                      controller: controller,
                      activityRepository: _ActivityRepository(
                        activities: activities,
                        gate: activitiesGate,
                        error: activitiesError,
                      ),
                      pushRegistrationStatus: pushRegistrationStatus,
                    ),
                  )
                : const Scaffold(body: Text('pushed')),
          );
        },
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return controller;
}

Future<GuardianChildController> _pumpProductionDashboard(
  WidgetTester tester, {
  required Size physicalSize,
  required double devicePixelRatio,
  required FakeViewPadding physicalPadding,
  required List<ActivitySummaryDto> activities,
  required List<ChildSummaryDto> children,
  PushRegistrationStatusController? pushRegistrationStatus,
  ValueChanged<String>? onPushRoute,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.padding = physicalPadding;
  tester.view.viewPadding = physicalPadding;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  final controller = GuardianChildController(_ChildRepository(children));
  addTearDown(controller.dispose);
  await controller.loadChildren();

  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) {
        final name = settings.name;
        if (name != null && name != '/') onPushRoute?.call(name);
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => name == null || name == '/'
              ? GuardianSidebarShell(
                  onSwitchProfile: (_) {},
                  destinations: [
                    GuardianNavItem(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home,
                      label: '홈',
                      builder: (_) => GuardianHomeScreen(
                        controller: controller,
                        activityRepository: _ActivityRepository(
                          activities: activities,
                        ),
                        pushRegistrationStatus: pushRegistrationStatus,
                      ),
                    ),
                  ],
                )
              : const Scaffold(body: Text('pushed')),
        );
      },
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

PushRegistrationStatusController _failedPushStatus() {
  final status = PushRegistrationStatusController()
    ..report(
      const PushTokenRegistrationFailure(
        type: PushTokenRegistrationFailureType.storageUnavailable,
        code: 'DEVICE_TOKEN_STORAGE_UNAVAILABLE',
      ),
    );
  return status;
}

List<ActivitySummaryDto> _many(int count) => [
  for (var i = 0; i < count; i++)
    ActivitySummaryDto(
      activityId: 10 + i,
      title: '활동 ${i + 1}',
      drawingType: const ActivityDrawingTypeDto(code: 'HTP', name: '집·나무·사람'),
      inputMethod: 'CANVAS',
      sessionStatus: 'COMPLETED',
      selectedEmotions: const ['HAPPY'],
      thumbnailUrl: null,
      analysisStatus: 'COMPLETED',
      // 첫 항목만 완료된 리포트를 달아 최신 리포트 버튼 키를 확정한다.
      report: i == 1
          ? const ActivityReportSummaryDto(
              reportId: 11,
              reportStatus: 'COMPLETED',
            )
          : null,
      startedAt: '2026-08-02T10:00:00',
      completedAt: '2026-08-02T10:20:00',
    ),
];

ApiPage<ActivitySummaryDto> _page(List<ActivitySummaryDto> content) =>
    ApiPage<ActivitySummaryDto>(
      content: content,
      page: 0,
      size: content.isEmpty ? 8 : content.length,
      totalElements: content.length,
      totalPages: 1,
      hasNext: false,
    );

ChildSummaryDto _child({required int id, required String nickname}) =>
    ChildSummaryDto(
      childId: id,
      nickname: nickname,
      birthDate: '2019-04-05',
      age: 7,
      profileImageUrl: null,
      preferredCharacter: 'BASE',
      questionDifficulty: 'PRESCHOOL',
      tutorialStatus: 'NOT_STARTED',
      relationshipType: 'MOTHER',
      recentActivity: const ChildRecentActivityDto(
        lastActivityAt: null,
        totalActivityCount: 3,
      ),
    );

final class _ChildRepository implements ChildRepository {
  _ChildRepository(this.children);

  final List<ChildSummaryDto> children;

  @override
  Future<List<ChildSummaryDto>> getChildren() async => children;

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) =>
      throw UnimplementedError();

  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteChild(int childId) => throw UnimplementedError();

  @override
  Future<ChildDetailDto> getChild(int childId) => throw UnimplementedError();

  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) =>
      throw UnimplementedError();

  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) => throw UnimplementedError();
}

final class _ActivityRepository implements ActivityRepository {
  _ActivityRepository({this.activities, this.gate, this.error});

  final List<ActivitySummaryDto>? activities;
  final Completer<ApiPage<ActivitySummaryDto>>? gate;
  final Object? error;

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) {
    if (gate case final gate?) return gate.future;
    if (error case final error?) return Future.error(error);
    return Future.value(_page(activities ?? const []));
  }

  @override
  Future<ActivityDetailDto> getActivity(int activityId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteActivity(int activityId) => throw UnimplementedError();

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadImage(String url) => throw UnimplementedError();
}
