import 'dart:async';
import 'dart:ui' as ui;

import 'package:dodam/app/router/app_router.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child_mode/data/child_home_intro_store.dart';
import 'package:dodam/features/child_mode/domain/dodam_costume.dart';
import 'package:dodam/features/child_mode/presentation/screens/child_mode_screens.dart';
import 'package:dodam/features/child_mode/presentation/widgets/activity_guide_dialog.dart';
import 'package:dodam/features/drawing/application/drawing_session_start_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/screens/input_method_select_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _child = ChildSummaryDto(
  childId: 7,
  nickname: '도담',
  birthDate: '2020-01-01',
  age: 6,
  profileImageUrl: null,
  preferredCharacter: null,
  questionDifficulty: 'EASY',
  tutorialStatus: 'DONE',
  relationshipType: 'PARENT',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

ChildSummaryDto _childWith({
  required int childId,
  required String nickname,
  String? preferredCharacter,
  String? profileImageUrl,
}) => ChildSummaryDto(
  childId: childId,
  nickname: nickname,
  birthDate: '2020-01-01',
  age: 6,
  profileImageUrl: profileImageUrl,
  preferredCharacter: preferredCharacter,
  questionDifficulty: 'EASY',
  tutorialStatus: 'DONE',
  relationshipType: 'PARENT',
  recentActivity: const ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

const _artDiary = DrawingTypeDto(
  drawingTypeId: 5,
  code: 'ART_DIARY',
  name: '그림일기',
  activityCategory: 'GENERAL',
  selectableBy: 'BOTH',
  recommendedAgeMin: 4,
  recommendedAgeMax: 12,
  guideText: '오늘 있었던 일을 그림으로 그려 볼까?',
  displayOrder: 1,
);

const _secondType = DrawingTypeDto(
  drawingTypeId: 9,
  code: 'HTP',
  name: '집·나무·사람 그림',
  activityCategory: 'ASSESSMENT',
  selectableBy: 'BOTH',
  recommendedAgeMin: null,
  recommendedAgeMax: null,
  guideText: null,
  displayOrder: 2,
);

/// 진행 중인 HTP 주제 세션. 재진입 판정은 inputMethod·currentStage·주제로 한다.
ActiveDrawingSessionDto _htpActiveSession({
  required String inputMethod,
  String currentStage = 'DRAWING',
  String drawingSubject = 'HOUSE',
  int stepOrder = 1,
  String htpStatus = 'IN_PROGRESS',
}) => ActiveDrawingSessionDto(
  drawingSessionId: 812,
  childId: 7,
  drawingType: const DrawingTypeSummaryDto(
    drawingTypeId: 9,
    code: 'HTP',
    name: '집·나무·사람 그림',
  ),
  inputMethod: inputMethod,
  sessionStatus: 'IN_PROGRESS',
  currentStage: currentStage,
  startedAt: '2026-07-29T01:00:00Z',
  latestDraft: null,
  activityContext: DrawingActivityContextDto(
    activityKind: 'HTP',
    htpAssessmentId: 55,
    htpStatus: htpStatus,
    stepOrder: stepOrder,
    drawingSubject: drawingSubject,
  ),
);

/// 앱 라우터와 같은 방식으로 화면을 감싼다.
///
/// [htpPhotoUploadEnabled]는 `main.dart`의 dart-define 기본값에 의존하지 않고
/// 테스트가 명시적으로 주입한다(S15P11B209-834).
Widget _wrap(Widget home, {bool htpPhotoUploadEnabled = false}) => MaterialApp(
  home: home,
  onGenerateRoute: (settings) {
    if (settings.name == AppRoutes.drawingInputMethod('7')) {
      final arguments = settings.arguments! as InputMethodSelectRouteArguments;
      return MaterialPageRoute<DrawingSessionResolution>(
        settings: settings,
        builder: (_) => InputMethodSelectScreen(
          childId: arguments.childId,
          drawingTypeId: arguments.drawingTypeId,
          title: arguments.title,
          description: arguments.description,
          icon: arguments.icon,
          accentColor: arguments.accentColor,
          repository: arguments.repository,
          existingDrawingSessionId: arguments.existingDrawingSessionId,
          restoredActivityContext: arguments.restoredActivityContext,
          htpAssessmentId: arguments.htpAssessmentId,
          // 실제 라우터(app_router.dart)와 같이 앱 수준 flag를 그대로 넘긴다.
          htpPhotoUploadEnabled: htpPhotoUploadEnabled,
        ),
      );
    }
    if (settings.name == AppRoutes.activityComplete('7')) {
      final arguments = settings.arguments! as ActivityCompleteRouteArguments;
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            Scaffold(body: Text('activity-complete-${arguments.sessionId}')),
      );
    }
    if (settings.name != AppRoutes.drawing('7')) return null;
    final arguments = settings.arguments! as DrawingRouteArguments;
    return MaterialPageRoute<DrawingRouteResult>(
      settings: settings,
      builder: (routeContext) => Scaffold(
        body: Column(
          children: [
            Text(
              'drawing-session-${arguments.sessionId}-resume-${arguments.resumeConversation}'
              '-auto-${arguments.autoRestoreDraft}-fresh-${arguments.startFresh}',
            ),
            Text('drawing-companion-${arguments.companion.code}'),
            TextButton(
              key: const ValueKey('leave-drawing'),
              onPressed: () => Navigator.of(
                routeContext,
              ).pop(const DrawingRouteResult.backToActivityEntry()),
              child: const Text('나가기'),
            ),
          ],
        ),
      ),
    );
  },
);

Future<void> _pumpCarouselHome(
  WidgetTester tester, {
  ChildSummaryDto child = _child,
  List<DodamCostume> costumes = DodamCostume.values,
  Future<bool> Function(int childId, String code)? onCharacterSelected,
}) async {
  await tester.pumpWidget(
    _wrap(
      ChildModeHomeScreen(
        child: child,
        drawingRepository: _FakeDrawingRepository(
          drawingTypes: const [_secondType, _artDiary],
        ),
        introStore: _FakeIntroStore(seen: {child.childId}),
        availableCostumes: costumes,
        onCharacterSelected: onCharacterSelected,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectCurrentCostume(
  WidgetTester tester,
  DodamCostume costume, {
  List<DodamCostume> costumes = DodamCostume.values,
}) {
  expect(find.text(costume.label), findsOneWidget);
  expect(find.byKey(ValueKey('costume-stage-${costume.code}')), findsOneWidget);
  final pageView = tester.widget<PageView>(
    find.byKey(const ValueKey('costume-carousel')),
  );
  expect(pageView.controller!.page, costumes.indexOf(costume).toDouble());
  expect(
    tester
        .widget<AnimatedContainer>(
          find.byKey(ValueKey('costume-indicator-${costume.code}')),
        )
        .constraints!
        .minWidth,
    26,
  );
  for (final other in costumes.where((item) => item != costume)) {
    expect(
      tester
          .widget<AnimatedContainer>(
            find.byKey(ValueKey('costume-indicator-${other.code}')),
          )
          .constraints!
          .minWidth,
      10,
    );
  }
  final semantics = tester.getSemantics(
    find.byKey(const ValueKey('costume-selection-semantics')),
  );
  expect(semantics.value, '${costume.label}, 선택됨');
  expect(semantics.flagsCollection.isSelected, ui.Tristate.isTrue);
}

void main() {
  testWidgets('아동 홈은 코스튬 캐러셀과 그림 그리기 버튼을 보여준다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_secondType, _artDiary],
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('costume-carousel')), findsOneWidget);
    expect(find.byKey(const ValueKey('draw-entry')), findsOneWidget);
    expect(find.text('그림 그리기'), findsOneWidget);
    // 새 활동 시작은 그림일기만 — HTP 카드는 홈에 없다.
    expect(find.byKey(const ValueKey('activity-9')), findsNothing);
    expect(find.text('집·나무·사람 그림'), findsNothing);
    // 지난 그림 보기(과거 그림 다시 보기) 입구는 그림 그리기 옆 secondary로 노출한다.
    expect(find.byKey(const ValueKey('past-drawings-entry')), findsOneWidget);
    expect(find.text('지난 그림 보기'), findsOneWidget);
  });

  testWidgets('캐릭터를 고르면 그 아이의 preferredCharacter로 저장하도록 알린다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_secondType, _artDiary],
    );
    final selections = <(int, String)>[];

    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          onCharacterSelected: (childId, code) async {
            selections.add((childId, code));
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 다음 캐릭터로 넘기면 base -> princess.
    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pumpAndSettle();
    // 디바운스가 지나야 저장 알림이 나간다(스와이프마다 보내지 않는다).
    await tester.pump(const Duration(milliseconds: 700));

    expect(selections, [(_child.childId, 'PRINCESS')]);
  });

  testWidgets('캐릭터 저장 실패는 이전 확정 캐릭터로 rollback하고 안내한다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_secondType, _artDiary],
    );
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          onCharacterSelected: (_, _) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('도담이'), findsOneWidget);
    expect(find.text('친구를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('캐러셀 마지막에서 다음은 BASE로 순환하고 표시·indicator·저장을 동기화한다', (
    tester,
  ) async {
    final selections = <(int, String)>[];
    await _pumpCarouselHome(
      tester,
      child: _childWith(
        childId: 7,
        nickname: '도담',
        preferredCharacter: 'OCTOPUS',
      ),
      onCharacterSelected: (childId, code) async {
        selections.add((childId, code));
        return true;
      },
    );
    _expectCurrentCostume(tester, DodamCostume.octopus);

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pumpAndSettle();
    _expectCurrentCostume(tester, DodamCostume.base);
    await tester.pump(const Duration(milliseconds: 700));

    expect(selections, [(7, 'BASE')]);
  });

  testWidgets('캐러셀 첫 항목에서 이전은 OCTOPUS로 순환하며 endpoint 화살표는 활성이다', (
    tester,
  ) async {
    await _pumpCarouselHome(tester);

    final previous = tester.getSemantics(
      find.byKey(const ValueKey('costume-prev')),
    );
    final next = tester.getSemantics(
      find.byKey(const ValueKey('costume-next')),
    );
    expect(previous.label, '이전 친구');
    expect(previous.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(next.label, '다음 친구');
    expect(next.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey('costume-prev'))).height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.byKey(const ValueKey('costume-prev')));
    await tester.pumpAndSettle();
    _expectCurrentCostume(tester, DodamCostume.octopus);

    final endpointNext = tester.getSemantics(
      find.byKey(const ValueKey('costume-next')),
    );
    expect(endpointNext.flagsCollection.isEnabled, ui.Tristate.isTrue);
  });

  testWidgets('캐릭터 수보다 많은 연속 다음 탭도 modulo 순환하고 마지막 값만 저장한다', (tester) async {
    final selections = <String>[];
    await _pumpCarouselHome(
      tester,
      onCharacterSelected: (_, code) async {
        selections.add(code);
        return true;
      },
    );

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('costume-next')));
    }
    await tester.pumpAndSettle();
    _expectCurrentCostume(tester, DodamCostume.dino);
    await tester.pump(const Duration(milliseconds: 700));

    expect(selections, ['DINO']);
  });

  testWidgets('캐릭터 수보다 많은 이전 탭과 좌우 교차 탭도 마지막 사용자 의도를 유지한다', (tester) async {
    final selections = <String>[];
    await _pumpCarouselHome(
      tester,
      onCharacterSelected: (_, code) async {
        selections.add(code);
        return true;
      },
    );

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('costume-prev')));
    }
    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.tap(find.byKey(const ValueKey('costume-prev')));
    await tester.tap(find.byKey(const ValueKey('costume-prev')));
    await tester.pumpAndSettle();
    _expectCurrentCostume(tester, DodamCostume.dino);
    await tester.pump(const Duration(milliseconds: 700));

    expect(selections, ['DINO']);
  });

  testWidgets('한 바퀴 돌아 확정 캐릭터로 복귀하면 동일 PATCH를 만들지 않는다', (tester) async {
    final selections = <String>[];
    await _pumpCarouselHome(
      tester,
      onCharacterSelected: (_, code) async {
        selections.add(code);
        return true;
      },
    );

    for (var i = 0; i < DodamCostume.values.length; i++) {
      await tester.tap(find.byKey(const ValueKey('costume-next')));
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));

    _expectCurrentCostume(tester, DodamCostume.base);
    expect(selections, isEmpty);
  });

  testWidgets('저장 in-flight 중 새 선택은 직렬화되고 늦은 실패가 최신 선택을 덮지 않는다', (
    tester,
  ) async {
    final requests = <String>[];
    final princessResult = Completer<bool>();
    final dinoResult = Completer<bool>();
    await _pumpCarouselHome(
      tester,
      onCharacterSelected: (_, code) {
        requests.add(code);
        return switch (code) {
          'PRINCESS' => princessResult.future,
          'DINO' => dinoResult.future,
          _ => Future.value(true),
        };
      },
    );

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(requests, ['PRINCESS']);

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(requests, ['PRINCESS']);
    _expectCurrentCostume(tester, DodamCostume.dino);

    princessResult.complete(false);
    await tester.pump();
    expect(requests, ['PRINCESS', 'DINO']);
    _expectCurrentCostume(tester, DodamCostume.dino);

    dinoResult.complete(true);
    await tester.pumpAndSettle();
    _expectCurrentCostume(tester, DodamCostume.dino);
  });

  testWidgets('같은 child rebuild는 index를 유지하고 childId 변경은 새 아이 확정값으로 맞춘다', (
    tester,
  ) async {
    final first = _childWith(
      childId: 7,
      nickname: '도담',
      preferredCharacter: 'PRINCESS',
    );
    await _pumpCarouselHome(tester, child: first);
    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pumpAndSettle();
    _expectCurrentCostume(tester, DodamCostume.dino);

    await _pumpCarouselHome(
      tester,
      child: _childWith(
        childId: 7,
        nickname: '도담 새 이름',
        preferredCharacter: 'PRINCESS',
      ),
    );
    _expectCurrentCostume(tester, DodamCostume.dino);

    await _pumpCarouselHome(
      tester,
      child: _childWith(
        childId: 8,
        nickname: '새봄',
        preferredCharacter: 'OCTOPUS',
      ),
    );
    _expectCurrentCostume(tester, DodamCostume.octopus);
  });

  testWidgets('빈 목록과 단일 목록은 예외·animation·저장 없이 안전하다', (tester) async {
    final selections = <String>[];
    await _pumpCarouselHome(tester, costumes: const []);
    expect(find.text('선택할 친구가 없어요'), findsNothing);
    expect(find.bySemanticsLabel('선택할 친구가 없어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('costume-prev')), findsNothing);
    expect(find.byKey(const ValueKey('costume-next')), findsNothing);
    expect(tester.takeException(), isNull);

    await _pumpCarouselHome(
      tester,
      costumes: const [DodamCostume.base],
      onCharacterSelected: (_, code) async {
        selections.add(code);
        return true;
      },
    );
    await tester.tap(find.byKey(const ValueKey('costume-prev')));
    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump(const Duration(milliseconds: 700));

    _expectCurrentCostume(
      tester,
      DodamCostume.base,
      costumes: const [DodamCostume.base],
    );
    expect(selections, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('화살표 탭 직후 dispose되어도 animation·저장 결과가 상태를 변경하지 않는다', (
    tester,
  ) async {
    final result = Completer<bool>();
    var calls = 0;
    await _pumpCarouselHome(
      tester,
      onCharacterSelected: (_, _) {
        calls++;
        return result.future;
      },
    );

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    expect(calls, 1);

    result.complete(false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending 저장이 없으면 서버 preferredCharacter snapshot으로 활동을 시작한다', (
    tester,
  ) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    final child = _childWith(
      childId: 7,
      nickname: '도담',
      preferredCharacter: 'BASE',
      profileImageUrl: 'https://example.invalid/child.jpg',
    );
    var characterPatchCalls = 0;
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: child,
          drawingRepository: repository,
          introStore: _FakeIntroStore(seen: {7}),
          onCharacterSelected: (_, _) async {
            characterPatchCalls++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('draw-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-guide-start')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(characterPatchCalls, 0);
    expect(find.text('drawing-companion-BASE'), findsOneWidget);
  });

  testWidgets('debounce 중 연속 활동 탭은 PATCH 성공 뒤 새 snapshot으로 세션을 한 번 만든다', (
    tester,
  ) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    final save = Completer<bool>();
    final patches = <String>[];
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _childWith(
            childId: 7,
            nickname: '도담',
            preferredCharacter: 'BASE',
          ),
          drawingRepository: repository,
          introStore: _FakeIntroStore(seen: {7}),
          onCharacterSelected: (_, code) {
            patches.add(code);
            return save.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pumpAndSettle();
    final drawEntry = tester.getCenter(
      find.byKey(const ValueKey('draw-entry')),
    );
    final firstEntryTap = await tester.startGesture(drawEntry, pointer: 11);
    final secondEntryTap = await tester.startGesture(drawEntry, pointer: 12);
    await firstEntryTap.up();
    await secondEntryTap.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-guide-start')), findsOneWidget);

    final start = tester.getCenter(
      find.byKey(const ValueKey('activity-guide-start')),
    );
    final first = await tester.startGesture(start, pointer: 1);
    final second = await tester.startGesture(start, pointer: 2);
    await first.up();
    await second.up();
    await tester.pump();

    expect(patches, ['PRINCESS']);
    expect(repository.createCalls, 0);

    save.complete(true);
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.text('drawing-companion-PRINCESS'), findsOneWidget);
  });

  testWidgets('활동 시작 settlement의 PATCH 실패는 서버 확정값으로 rollback해 시작한다', (
    tester,
  ) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    final save = Completer<bool>();
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _childWith(
            childId: 7,
            nickname: '도담',
            preferredCharacter: 'BASE',
          ),
          drawingRepository: repository,
          introStore: _FakeIntroStore(seen: {7}),
          onCharacterSelected: (_, _) => save.future,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('draw-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-guide-start')));
    await tester.pump();
    expect(repository.createCalls, 0);

    save.complete(false);
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.text('drawing-companion-BASE'), findsOneWidget);
  });

  testWidgets('저장 중 system back·dispose·child 변경은 이전 결과로 세션을 만들지 않는다', (
    tester,
  ) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    final save = Completer<bool>();
    final child = ValueNotifier<ChildSummaryDto>(
      _childWith(childId: 7, nickname: '도담', preferredCharacter: 'BASE'),
    );
    addTearDown(child.dispose);
    await tester.pumpWidget(
      _wrap(
        ValueListenableBuilder<ChildSummaryDto>(
          valueListenable: child,
          builder: (_, value, _) => ChildModeHomeScreen(
            child: value,
            drawingRepository: repository,
            introStore: _FakeIntroStore(seen: {7, 8}),
            onCharacterSelected: (_, _) => save.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('draw-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-guide-start')));
    await tester.pump();

    await tester.binding.handlePopRoute();
    child.value = _childWith(
      childId: 8,
      nickname: '새봄',
      preferredCharacter: 'DINO',
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    save.complete(true);
    await tester.pumpAndSettle();

    expect(repository.createCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('최초 안내 secondary는 현재 확정 캐릭터를 유지하고 PATCH 없이 완료한다', (tester) async {
    final store = _FakeIntroStore();
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    var characterPatchCalls = 0;
    final child = _childWith(
      childId: 7,
      nickname: '도담',
      preferredCharacter: 'DINO',
    );

    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: child,
          drawingRepository: repository,
          introStore: store,
          onCharacterSelected: (_, _) async {
            characterPatchCalls++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsOneWidget,
    );
    final mascot = tester.widget<Image>(
      find.byKey(const ValueKey('child-character-intro-mascot')),
    );
    expect(
      (mascot.image as AssetImage).assetName,
      'assets/characters/dodam_intro.png',
    );
    final titleSemantics = tester.getSemantics(
      find.text('반가워!\n함께할 도담이를 골라볼까?'),
    );
    expect(titleSemantics.flagsCollection.isHeader, isTrue);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('pick-character-from-intro')))
          .height,
      greaterThanOrEqualTo(48),
    );

    expect(find.text('친구 골라보기'), findsOneWidget);
    expect(find.text('지금 도담이로 시작할래'), findsOneWidget);

    final secondary = find.byKey(const ValueKey('choose-character-later'));
    final secondaryCenter = tester.getCenter(secondary);
    final firstTap = await tester.startGesture(secondaryCenter, pointer: 1);
    final secondTap = await tester.startGesture(secondaryCenter, pointer: 2);
    await firstTap.up();
    await secondTap.up();
    await tester.pumpAndSettle();
    expect(store.marked, [7]);
    expect(characterPatchCalls, 0);
    _expectCurrentCostume(tester, DodamCostume.dino);
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsNothing,
    );

    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: child,
          drawingRepository: repository,
          introStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsNothing,
    );
  });

  testWidgets('친구 골라보기는 실제 다음 화살표 저장 성공 뒤에만 intro를 완료한다', (tester) async {
    final store = _FakeIntroStore();
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    final save = Completer<bool>();
    final patches = <String>[];

    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          introStore: store,
          onCharacterSelected: (_, code) {
            patches.add(code);
            return save.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('pick-character-from-intro')));
    await tester.pumpAndSettle();

    expect(store.marked, isEmpty);
    expect(find.byKey(const ValueKey('costume-carousel')), findsOneWidget);
    expect(find.byKey(const ValueKey('child-character-guide')), findsOneWidget);
    expect(find.text('화살표를 눌러 함께할 도담이를 골라봐!'), findsOneWidget);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'costume-selector',
    );

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump(const Duration(milliseconds: 599));
    expect(patches, isEmpty);
    expect(store.marked, isEmpty);
    _expectCurrentCostume(tester, DodamCostume.princess);

    await tester.pump(const Duration(milliseconds: 1));
    expect(patches, ['PRINCESS']);
    expect(find.text('친구를 정하고 있어요'), findsOneWidget);
    expect(store.marked, isEmpty);

    save.complete(true);
    await tester.pumpAndSettle();
    expect(store.marked, [7]);
    expect(find.byKey(const ValueKey('child-character-guide')), findsNothing);
    expect(find.text('새 친구와 함께 시작해 볼까?'), findsOneWidget);
  });

  testWidgets('가이드는 실제 이전 화살표의 원형 순환과 PageView swipe를 저장한다', (tester) async {
    final store = _FakeIntroStore();
    final patches = <String>[];
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          introStore: store,
          onCharacterSelected: (_, code) async {
            patches.add(code);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-character-from-intro')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('costume-prev')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    _expectCurrentCostume(tester, DodamCostume.octopus);
    expect(patches, ['OCTOPUS']);
    expect(store.marked, [7]);

    final swipeStore = _FakeIntroStore();
    patches.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          introStore: swipeStore,
          onCharacterSelected: (_, code) async {
            patches.add(code);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-character-from-intro')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('costume-carousel')),
      const Offset(-320, 0),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    _expectCurrentCostume(tester, DodamCostume.princess);
    expect(patches, ['PRINCESS']);
    expect(swipeStore.marked, [7]);
  });

  testWidgets('가이드 저장 실패는 rollback·미완료 후 실제 재선택 성공을 허용한다', (tester) async {
    final store = _FakeIntroStore();
    final patches = <String>[];
    var shouldSucceed = false;
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: _FakeDrawingRepository(
            drawingTypes: const [_artDiary],
          ),
          introStore: store,
          onCharacterSelected: (_, code) async {
            patches.add(code);
            return shouldSucceed;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-character-from-intro')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    _expectCurrentCostume(tester, DodamCostume.base);
    expect(store.marked, isEmpty);
    expect(find.byKey(const ValueKey('child-character-guide')), findsOneWidget);
    expect(find.text('친구를 정하지 못했어요. 다시 골라볼까요?'), findsWidgets);

    shouldSucceed = true;
    await tester.tap(find.byKey(const ValueKey('costume-prev')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(patches, ['PRINCESS', 'OCTOPUS']);
    expect(store.marked, [7]);
    _expectCurrentCostume(tester, DodamCostume.octopus);
  });

  testWidgets('안내와 가이드의 system back은 현재 진입만 닫고 완료를 저장하지 않는다', (tester) async {
    final store = _FakeIntroStore();
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          introStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsOneWidget,
    );
    expect(store.marked, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(store.marked, isEmpty);
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsNothing,
    );

    // 같은 화면에서 rebuild되어도 즉시 다시 열리지 않는다.
    await tester.pump();
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsNothing,
    );

    // 다음 정상 진입에는 미완료 상태라 다시 나타난다.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          introStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('pick-character-from-intro')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('child-character-guide')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('child-character-guide')), findsNothing);
    expect(store.marked, isEmpty);
  });

  testWidgets('가이드 저장 중 dispose와 이전 child의 늦은 성공은 intro를 완료하지 않는다', (
    tester,
  ) async {
    final store = _FakeIntroStore();
    final save = Completer<bool>();
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: _FakeDrawingRepository(
            drawingTypes: const [_artDiary],
          ),
          introStore: store,
          onCharacterSelected: (_, _) => save.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-character-from-intro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.pumpWidget(const SizedBox.shrink());
    save.complete(true);
    await tester.pump();
    expect(store.marked, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('확정 캐릭터로 한 바퀴 복귀하면 PATCH·intro 완료 없이 가이드를 유지한다', (tester) async {
    final store = _FakeIntroStore();
    final patches = <String>[];
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: _FakeDrawingRepository(
            drawingTypes: const [_artDiary],
          ),
          introStore: store,
          onCharacterSelected: (_, code) async {
            patches.add(code);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-character-from-intro')));
    await tester.pumpAndSettle();

    for (var i = 0; i < DodamCostume.values.length; i++) {
      await tester.tap(find.byKey(const ValueKey('costume-next')));
    }
    await tester.pump(const Duration(milliseconds: 700));

    _expectCurrentCostume(tester, DodamCostume.base);
    expect(patches, isEmpty);
    expect(store.marked, isEmpty);
    expect(find.byKey(const ValueKey('child-character-guide')), findsOneWidget);
  });

  testWidgets('childId 전환은 이전 아이의 늦은 저장 성공을 버리고 intro 상태를 분리한다', (
    tester,
  ) async {
    final store = _FakeIntroStore();
    final save = Completer<bool>();
    final child = ValueNotifier<ChildSummaryDto>(_child);
    addTearDown(child.dispose);
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    final otherChild = _childWith(
      childId: 8,
      nickname: '새봄',
      preferredCharacter: 'DINO',
    );

    await tester.pumpWidget(
      _wrap(
        ValueListenableBuilder<ChildSummaryDto>(
          valueListenable: child,
          builder: (_, value, _) => ChildModeHomeScreen(
            child: value,
            drawingRepository: repository,
            introStore: store,
            onCharacterSelected: (_, _) => save.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-character-from-intro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump(const Duration(milliseconds: 600));

    child.value = otherChild;
    await tester.pump();
    save.complete(true);
    await tester.pumpAndSettle();

    expect(store.marked, isEmpty);
    _expectCurrentCostume(tester, DodamCostume.dino);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: otherChild,
          drawingRepository: repository,
          introStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('choose-character-later')));
    await tester.pumpAndSettle();
    expect(store.marked, [8]);
    expect(store.seen, {8});
  });

  testWidgets('intro 저장 실패는 홈을 막지 않고 다음 정상 진입에서 안내를 다시 표시한다', (tester) async {
    final store = _FakeIntroStore(markFailure: StateError('storage failed'));
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          introStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choose-character-later')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsNothing,
    );
    expect(store.marked, [7]);
    expect(store.seen, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          introStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('active session dialog을 닫아도 최초 캐릭터 안내를 뒤이어 열지 않는다', (
    tester,
  ) async {
    final store = _FakeIntroStore();
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary],
      activeSession: const ActiveDrawingSessionDto(
        drawingSessionId: 555,
        childId: 7,
        drawingType: DrawingTypeSummaryDto(
          drawingTypeId: 5,
          code: 'ART_DIARY',
          name: '그림일기',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
        startedAt: '2026-07-26T01:00:00Z',
        latestDraft: null,
      ),
    );
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          introStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('이어 그리기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsNothing,
    );
    expect(store.readChildIds, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsNothing,
    );
    expect(store.readChildIds, isEmpty);
  });

  testWidgets('prepared UPLOAD 자동 진입은 intro 조회보다 먼저 대화 route를 연다', (
    tester,
  ) async {
    final store = _FakeIntroStore();
    const prepared = DrawingSessionResolution(
      sessionId: 834,
      currentStage: 'CONVERSING',
      inputMethod: 'UPLOAD',
      activityContext: DrawingActivityContextDto(
        activityKind: 'HTP',
        htpAssessmentId: 84,
        stepOrder: 1,
        drawingSubject: 'HOUSE',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: _FakeDrawingRepository(
            drawingTypes: const [_artDiary],
          ),
          introStore: store,
          preparedResolution: prepared,
          autoStartPrepared: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('drawing-session-834-resume-true-auto-false-fresh-false'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsNothing,
    );
    expect(store.readChildIds, isEmpty);
  });

  testWidgets('rebuild·background·resume에도 최초 dialog를 중복 생성하지 않는다', (
    tester,
  ) async {
    final store = _FakeIntroStore();
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    final home = _wrap(
      ChildModeHomeScreen(
        child: _child,
        drawingRepository: repository,
        introStore: store,
      ),
    );
    await tester.pumpWidget(home);
    await tester.pumpAndSettle();
    await tester.pumpWidget(home);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsOneWidget,
    );
    expect(store.readChildIds, [7]);
  });

  testWidgets('단계형 가이드는 320x640·태블릿·가로·text scale 2.0에서 동작한다', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final configuration in const [
      (Size(320, 640), 2.0),
      (Size(800, 1280), 1.0),
      (Size(1280, 800), 1.0),
    ]) {
      await tester.binding.setSurfaceSize(configuration.$1);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: configuration.$1,
            textScaler: TextScaler.linear(configuration.$2),
          ),
          child: _wrap(
            ChildModeHomeScreen(
              child: _child,
              drawingRepository: _FakeDrawingRepository(
                drawingTypes: const [_artDiary],
              ),
              introStore: _FakeIntroStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pick = find.byKey(const ValueKey('pick-character-from-intro'));
      await tester.ensureVisible(pick);
      await tester.pump();
      await tester.tap(pick);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('child-character-guide')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('costume-prev'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull, reason: '${configuration.$1}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('active session 확인 중에는 최초 안내를 띄우지 않는다', (tester) async {
    final store = _FakeIntroStore();
    final active = Completer<ActiveDrawingSessionDto?>();
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary],
      activeSessionCompleter: active,
    );
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          introStore: store,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsNothing,
    );
    expect(store.readChildIds, isEmpty);

    active.complete(null);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('최초 안내는 320x640·text scale 2.0에서 overflow가 없다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _FakeIntroStore();
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: _wrap(
          ChildModeHomeScreen(
            child: _child,
            drawingRepository: repository,
            introStore: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('최초 안내는 Pixel Tablet 세로·가로에서 overflow가 없다', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [Size(800, 1280), Size(1280, 800)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(
            child: _child,
            drawingRepository: _FakeDrawingRepository(
              drawingTypes: const [_artDiary],
            ),
            introStore: _FakeIntroStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('child-character-intro-dialog')),
        findsOneWidget,
        reason: '$size',
      );
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('그림 유형을 불러오는 동안 로딩 상태를 보여준다', (tester) async {
    final completer = Completer<ApiPage<DrawingTypeDto>>();
    final repository = _FakeDrawingRepository(typesCompleter: completer);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pump();

    expect(find.byType(AppLoadingView), findsOneWidget);

    completer.complete(
      const ApiPage(
        content: [_artDiary],
        page: 0,
        size: 1,
        totalElements: 1,
        totalPages: 1,
        hasNext: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draw-entry')), findsOneWidget);
  });

  testWidgets('그림 유형을 불러오지 못하면 오류와 다시 시도를 보여준다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary],
      getTypesFailure: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
      failGetTypesOnce: true,
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorView), findsOneWidget);
    expect(find.byKey(const ValueKey('draw-entry')), findsNothing);

    await tester.ensureVisible(find.text('다시 시도'));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('draw-entry')), findsOneWidget);
  });

  testWidgets('지원하는 그림 유형이 없으면 빈 상태를 보여준다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const []);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppEmptyView), findsOneWidget);
  });

  testWidgets('그림 그리기를 탭하면 그림일기 안내 팝업이 표시된다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('draw-entry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-guide-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-guide-cancel')), findsOneWidget);
    expect(find.text('그림일기'), findsWidgets);
    expect(find.text('오늘 있었던 일을 그림으로 그려 볼까?'), findsWidgets);
    expect(repository.createCalls, 0);
  });

  testWidgets('취소를 누르면 세션을 만들지 않고 홈에 남는다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('draw-entry')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('activity-guide-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
    expect(find.byKey(const ValueKey('draw-entry')), findsOneWidget);
    expect(repository.createCalls, 0);
    // 안내 팝업을 띄우기 전에 이어 그리기 대상이 있는지 한 번 확인한다.
    expect(repository.getActiveSessionCalls, 1);
  });

  testWidgets('스크림을 탭해도 세션을 만들지 않고 홈에 남는다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('draw-entry')));
    await tester.pumpAndSettle();

    // 팝업 바깥(스크림)을 탭해 취소와 같은 효과를 낸다.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
    expect(repository.createCalls, 0);
  });

  testWidgets('그림일기 시작하기는 CANVAS 세션을 만들고 바로 이동한다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('draw-entry')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('activity-guide-start')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(repository.lastCreateRequest?.childId, 7);
    expect(repository.lastCreateRequest?.drawingTypeId, 5);
    expect(repository.lastCreateRequest?.inputMethod, 'CANVAS');
    expect(
      find.text('drawing-session-900-resume-false-auto-false-fresh-true'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('input-method-photo')), findsNothing);
  });

  testWidgets('기존 활성 세션이 있으면 그대로 재개하고 새 세션을 만들지 않는다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary],
      activeSession: const ActiveDrawingSessionDto(
        drawingSessionId: 321,
        childId: 7,
        drawingType: DrawingTypeSummaryDto(
          drawingTypeId: 5,
          code: 'ART_DIARY',
          name: '그림일기',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'CONVERSING',
        startedAt: '2026-07-26T01:00:00Z',
        latestDraft: null,
      ),
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    // 진행 중 활동 확인은 활동 종류를 선택하기 전에 한 번만 수행한다.
    expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
    expect(find.text('이어 그리기'), findsOneWidget);
    await tester.tap(find.text('이어 그리기'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 0);
    expect(
      find.text('drawing-session-321-resume-true-auto-true-fresh-false'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('leave-drawing')));
    await tester.pumpAndSettle();

    // 캔버스에서 뒤로 나오면 활성 세션을 다시 조회하고 같은 팝업을 복원한다.
    expect(repository.getActiveSessionCalls, 2);
    expect(find.text('이어 그리기'), findsOneWidget);
    expect(find.text('새로 그리기'), findsOneWidget);
  });

  testWidgets('전시관 등 다른 화면이 홈 위에 있으면 이어 그리기 팝업을 띄우지 않는다', (tester) async {
    final completer = Completer<ActiveDrawingSessionDto?>();
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary],
      activeSessionCompleter: completer,
    );
    final nav = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: ChildModeHomeScreen(child: _child, drawingRepository: repository),
      ),
    );
    await tester.pump();

    // 진입 확인(활성 세션 조회)이 끝나기 전에 홈 위에 다른 화면(전시관 대역)을 올린다.
    unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('상단-화면')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 이제서야 활성 세션이 있다고 응답한다.
    completer.complete(
      const ActiveDrawingSessionDto(
        drawingSessionId: 321,
        childId: 7,
        drawingType: DrawingTypeSummaryDto(
          drawingTypeId: 5,
          code: 'ART_DIARY',
          name: '그림일기',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'CONVERSING',
        startedAt: '2026-07-26T01:00:00Z',
        latestDraft: null,
      ),
    );
    await tester.pumpAndSettle();

    // 홈이 최상단이 아니므로 이어 그리기 팝업이 그 화면 위에 뜨지 않는다.
    expect(find.text('상단-화면'), findsOneWidget);
    expect(find.text('이어 그리기'), findsNothing);
    expect(find.text('그리던 그림이 있어요'), findsNothing);
  });

  testWidgets('저장된 초안이 없는 활성 세션도 재개와 새 활동을 선택한다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary],
      activeSession: const ActiveDrawingSessionDto(
        drawingSessionId: 555,
        childId: 7,
        drawingType: DrawingTypeSummaryDto(
          drawingTypeId: 5,
          code: 'ART_DIARY',
          name: '그림일기',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
        startedAt: '2026-07-26T01:00:00Z',
        latestDraft: null,
      ),
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
    expect(find.text('이어 그리기'), findsOneWidget);
    expect(repository.createCalls, 0);

    await tester.tap(find.text('이어 그리기'));
    await tester.pumpAndSettle();

    expect(
      find.text('drawing-session-555-resume-false-auto-true-fresh-false'),
      findsOneWidget,
    );
  });

  testWidgets('새로 그리기를 고른 뒤 그림일기를 선택하면 새 캔버스로 이동한다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary, _secondType],
      activeSession: const ActiveDrawingSessionDto(
        drawingSessionId: 555,
        childId: 7,
        drawingType: DrawingTypeSummaryDto(
          drawingTypeId: 9,
          code: 'HTP',
          name: '집·나무·사람 그림',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
        startedAt: '2026-07-26T01:00:00Z',
        latestDraft: null,
      ),
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('새로 그리기'), findsOneWidget);
    await tester.tap(find.text('새로 그리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('draw-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-guide-start')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(
      repository.lastCreateRequest?.drawingTypeId,
      _artDiary.drawingTypeId,
    );
    expect(repository.lastCreateRequest?.inputMethod, 'CANVAS');
    expect(repository.lastCreateRequest?.replaceActive, isTrue);
    expect(
      find.text('drawing-session-900-resume-false-auto-false-fresh-true'),
      findsOneWidget,
    );
  });

  group('HTP 재진입 복구', () {
    Future<void> resumeActive(WidgetTester tester) async {
      await tester.pumpAndSettle();
      expect(find.text('이어 그리기'), findsOneWidget);
      await tester.tap(find.text('이어 그리기'));
      await tester.pumpAndSettle();
    }

    testWidgets('flag false의 HOUSE 다음 TREE 선택에는 사진 CTA가 없고 API 호출이 0회다', (
      tester,
    ) async {
      final repository = _FakeDrawingRepository(
        drawingTypes: const [_secondType],
        activeSession: _htpActiveSession(
          inputMethod: 'CANVAS',
          currentStage: 'REFLECTION',
        ),
      );

      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(child: _child, drawingRepository: repository),
        ),
      );
      await resumeActive(tester);

      // 다음 주제 입력 방식 선택 화면이 복원된다.
      expect(find.byKey(const ValueKey('input-method-canvas')), findsOneWidget);
      expect(find.byKey(const ValueKey('input-method-photo')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-camera')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-gallery')), findsNothing);
      // Canvas나 끝난 대화로 돌아가지 않는다.
      expect(find.textContaining('drawing-session-'), findsNothing);
      // 사용자가 고르기 전에는 전환·생성 API가 나가지 않는다.
      expect(repository.nextStepCalls, 0);
      expect(repository.htpStartCalls, 0);
      expect(repository.createCalls, 0);
    });

    testWidgets('flag false의 TREE 다음 PERSON 선택에도 사진 CTA가 없고 API 호출이 0회다', (
      tester,
    ) async {
      final repository = _FakeDrawingRepository(
        drawingTypes: const [_secondType],
        activeSession: _htpActiveSession(
          inputMethod: 'UPLOAD',
          currentStage: 'REFLECTION',
          drawingSubject: 'TREE',
          stepOrder: 2,
        ),
      );

      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(child: _child, drawingRepository: repository),
        ),
      );
      await resumeActive(tester);

      // UPLOAD 세션이지만 stage가 REFLECTION이라 사진 복원이 아니라 전환
      // 선택으로 간다.
      expect(find.byKey(const ValueKey('input-method-canvas')), findsOneWidget);
      expect(find.byKey(const ValueKey('input-method-photo')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-camera')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-gallery')), findsNothing);
      expect(repository.nextStepCalls, 0);
      expect(repository.htpStartCalls, 0);
    });

    testWidgets('flag false의 UPLOAD + DRAWING 재진입은 세션을 보존하고 홈에서 안내한다', (
      tester,
    ) async {
      final repository = _FakeDrawingRepository(
        drawingTypes: const [_secondType],
        activeSession: _htpActiveSession(inputMethod: 'UPLOAD'),
      );

      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(child: _child, drawingRepository: repository),
        ),
      );
      await resumeActive(tester);

      expect(find.byKey(const ValueKey('input-method-photo')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-camera')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-gallery')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-canvas')), findsNothing);
      expect(find.textContaining('사진으로 시작한 활동은 지금 이어갈 수 없어요'), findsOneWidget);
      expect(find.textContaining('drawing-session-'), findsNothing);
      expect(repository.createCalls, 0);
      expect(repository.htpStartCalls, 0);
      expect(repository.nextStepCalls, 0);
      expect(repository.completeAssessmentCalls, 0);
      expect(repository.deleteSessionCalls, 0);
    });

    testWidgets('flag true의 UPLOAD + DRAWING 재진입은 기존 사진 복원 흐름을 유지한다', (
      tester,
    ) async {
      final repository = _FakeDrawingRepository(
        drawingTypes: const [_secondType],
        activeSession: _htpActiveSession(inputMethod: 'UPLOAD'),
      );

      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(
            child: _child,
            drawingRepository: repository,
            htpPhotoUploadEnabled: true,
          ),
          htpPhotoUploadEnabled: true,
        ),
      );
      await resumeActive(tester);

      expect(find.byKey(const ValueKey('input-method-camera')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('input-method-gallery')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('input-method-canvas')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-back')), findsNothing);
      expect(repository.createCalls, 0);
      expect(repository.htpStartCalls, 0);
      expect(repository.nextStepCalls, 0);

      await tester.tap(find.byKey(const ValueKey('input-method-cancel')));
      await tester.pumpAndSettle();
      expect(repository.deleteSessionCalls, 0);
    });

    testWidgets('PERSON + COMPLETED 재진입은 감정 화면 없이 complete만 1회 복구한다', (
      tester,
    ) async {
      final repository = _FakeDrawingRepository(
        drawingTypes: const [_secondType],
        activeSession: _htpActiveSession(
          inputMethod: 'CANVAS',
          currentStage: 'COMPLETED',
          drawingSubject: 'PERSON',
          stepOrder: 3,
          // steps/next는 이미 끝났고 complete만 남은 상태.
          htpStatus: 'IN_PROGRESS',
        ),
      );

      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(child: _child, drawingRepository: repository),
        ),
      );
      await resumeActive(tester);

      // Reflection·steps/next를 다시 부르지 않는다.
      expect(repository.saveHtpReflectionCalls, 0);
      expect(repository.nextStepCalls, 0);
      expect(repository.htpStartCalls, 0);
      // 남은 complete만 정확히 1회.
      expect(repository.completeAssessmentCalls, 1);
      // 감정 선택 화면을 띄우지 않고 완료 화면으로 간다.
      expect(find.text('내 마음 고르기'), findsNothing);
      expect(find.text('activity-complete-812'), findsOneWidget);
    });

    testWidgets('PERSON + COMPLETED + ANALYZING이면 complete를 호출하지 않는다', (
      tester,
    ) async {
      final repository = _FakeDrawingRepository(
        drawingTypes: const [_secondType],
        activeSession: _htpActiveSession(
          inputMethod: 'UPLOAD',
          currentStage: 'COMPLETED',
          drawingSubject: 'PERSON',
          stepOrder: 3,
          // complete가 이미 성공한 상태 — 새 Key로 보내면 409다.
          htpStatus: 'ANALYZING',
        ),
      );

      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(child: _child, drawingRepository: repository),
        ),
      );
      await resumeActive(tester);

      expect(repository.completeAssessmentCalls, 0);
      expect(repository.saveHtpReflectionCalls, 0);
      expect(repository.nextStepCalls, 0);
      // UPLOAD 세션이지만 stage가 COMPLETED라 사진 복원으로 가지 않는다.
      expect(find.byKey(const ValueKey('input-method-camera')), findsNothing);
      expect(find.text('activity-complete-812'), findsOneWidget);
    });

    testWidgets('complete 실패 후 다시 진입하면 complete만 재시도한다', (tester) async {
      final repository = _FakeDrawingRepository(
        drawingTypes: const [_secondType],
        activeSession: _htpActiveSession(
          inputMethod: 'CANVAS',
          currentStage: 'COMPLETED',
          drawingSubject: 'PERSON',
          stepOrder: 3,
          htpStatus: 'IN_PROGRESS',
        ),
        failCompleteAssessmentOnce: true,
      );

      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(
            key: const ValueKey('first-entry'),
            child: _child,
            drawingRepository: repository,
          ),
        ),
      );
      await resumeActive(tester);

      // 첫 시도는 실패해 완료 화면으로 가지 않고 홈에 남는다(오류만 안내).
      expect(repository.completeAssessmentCalls, 1);
      expect(find.text('activity-complete-812'), findsNothing);
      expect(find.byKey(const ValueKey('costume-carousel')), findsOneWidget);

      // 복구는 화면 진입 시점에만 판단하므로, 재시도는 아동 모드에 다시
      // 들어오는 것(앱 재시작·보호자 모드 왕복)으로 이뤄진다. 새 key로
      // 새 State를 만들어 그 재진입을 재현한다.
      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(
            key: const ValueKey('second-entry'),
            child: _child,
            drawingRepository: repository,
          ),
        ),
      );
      await resumeActive(tester);

      expect(repository.completeAssessmentCalls, 2);
      // 재시도에서도 Reflection·steps/next는 0회를 유지한다.
      expect(repository.saveHtpReflectionCalls, 0);
      expect(repository.nextStepCalls, 0);
      expect(find.text('activity-complete-812'), findsOneWidget);
    });
  });

  testWidgets('좁은 화면과 2배 텍스트에서도 오버플로가 없다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary, _secondType],
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2.0),
        ),
        child: _wrap(
          ChildModeHomeScreen(child: _child, drawingRepository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('draw-entry')));
    await tester.tap(find.byKey(const ValueKey('draw-entry')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('안내 팝업도 좁은 화면과 2배 텍스트에서 오버플로가 없다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completer = Completer<DrawingSessionResolution>();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2.0),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showActivityGuideDialog<DrawingSessionResolution>(
                      context: context,
                      title: '그림일기',
                      description: '오늘 있었던 일을 아주 길게 자세히 적어 보면서 그림으로도 함께 그려 볼까?',
                      icon: Icons.menu_book_rounded,
                      accentColor: AppColors.tangerine,
                      onStart: () => completer.future,
                    ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('activity-guide-start')), findsOneWidget);
  });
}

final class _FakeDrawingRepository
    implements
        DrawingRepository,
        HtpDrawingRepository,
        DrawingSessionDiscarder {
  _FakeDrawingRepository({
    this.drawingTypes = const [],
    this.activeSession,
    this.getTypesFailure,
    this.failGetTypesOnce = false,
    this.failCompleteAssessmentOnce = false,
    this.typesCompleter,
    this.activeSessionCompleter,
  });

  final List<DrawingTypeDto> drawingTypes;
  final ActiveDrawingSessionDto? activeSession;
  final Object? getTypesFailure;
  bool failGetTypesOnce;
  bool failCompleteAssessmentOnce;
  final Completer<ApiPage<DrawingTypeDto>>? typesCompleter;

  /// 활성 세션 응답을 테스트가 원하는 시점에 완료시키기 위한 지연 통로.
  final Completer<ActiveDrawingSessionDto?>? activeSessionCompleter;

  int getDrawingTypesCalls = 0;
  int getActiveSessionCalls = 0;
  int createCalls = 0;
  int htpStartCalls = 0;
  int nextStepCalls = 0;
  int saveHtpReflectionCalls = 0;
  int completeAssessmentCalls = 0;
  int deleteSessionCalls = 0;
  final List<String> completeAssessmentKeys = [];
  CreateDrawingSessionRequestDto? lastCreateRequest;
  StartHtpAssessmentRequestDto? lastHtpRequest;

  /// 재진입 복구 경로에서는 주제 전환이 절대 일어나면 안 된다.
  @override
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
    required String idempotencyKey,
  }) async {
    nextStepCalls += 1;
    throw StateError('재진입 복구에서 steps/next를 부르면 안 된다.');
  }

  /// HTP 흐름에서 Drawing Session Reflection은 호출 대상이 아니다.
  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    throw StateError('HTP 흐름에서 Drawing Session Reflection을 부르면 안 된다.');
  }

  @override
  Future<void> saveHtpReflection(
    int assessmentId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    saveHtpReflectionCalls += 1;
  }

  @override
  Future<void> completeHtpAssessment(
    int assessmentId, {
    required String idempotencyKey,
  }) async {
    completeAssessmentCalls += 1;
    completeAssessmentKeys.add(idempotencyKey);
    if (failCompleteAssessmentOnce) {
      failCompleteAssessmentOnce = false;
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
  }

  @override
  Future<void> deleteSession(int sessionId) async {
    deleteSessionCalls += 1;
  }

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) async {
    getDrawingTypesCalls += 1;
    if (typesCompleter case final completer?) return completer.future;
    if (getTypesFailure case final failure? when failGetTypesOnce) {
      failGetTypesOnce = false;
      throw failure;
    }
    return ApiPage(
      content: drawingTypes,
      page: 0,
      size: drawingTypes.length,
      totalElements: drawingTypes.length,
      totalPages: drawingTypes.isEmpty ? 0 : 1,
      hasNext: false,
    );
  }

  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async {
    getActiveSessionCalls += 1;
    if (activeSessionCompleter != null) return activeSessionCompleter!.future;
    return activeSession;
  }

  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async {
    createCalls += 1;
    lastCreateRequest = request;
    return DrawingSessionDto.fromCreateJson({
      'drawingSessionId': 900,
      'childId': request.childId,
      'drawingType': {
        'drawingTypeId': request.drawingTypeId,
        'code': 'ART_DIARY',
        'name': '그림일기',
      },
      'inputMethod': request.inputMethod,
      'title': null,
      'sessionStatus': 'DRAWING',
      'currentStage': 'DRAWING',
      'selectedEmotions': null,
      'expressedEmotionText': null,
      'startedAt': request.clientStartedAt,
      'completedAt': null,
      'conversation': null,
      'latestAnalysis': null,
      'assets': [],
    });
  }

  @override
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  ) async {
    htpStartCalls += 1;
    lastHtpRequest = request;
    return const HtpAssessmentDto(
      htpAssessmentId: 91,
      status: 'IN_PROGRESS',
      expiresAt: '2026-07-30T01:00:00Z',
      currentStep: HtpAssessmentStepDto(
        stepOrder: 1,
        drawingSubject: 'HOUSE',
        drawingSessionId: 901,
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
      ),
      allStepsCompleted: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeIntroStore implements ChildHomeIntroStore {
  _FakeIntroStore({Set<int>? seen, this.markFailure}) : seen = {...?seen};

  final Set<int> seen;
  final Object? markFailure;
  final List<int> readChildIds = [];
  final List<int> marked = [];

  @override
  Future<bool> hasSeen(int childId) async {
    readChildIds.add(childId);
    return seen.contains(childId);
  }

  @override
  Future<void> markSeen(int childId) async {
    marked.add(childId);
    if (markFailure case final failure?) throw failure;
    seen.add(childId);
  }
}
