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
import 'package:dodam/features/child_mode/presentation/widgets/character_carousel_spotlight.dart';
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
    expect(find.text('새로 그리기'), findsOneWidget);
    // 새 활동 시작은 그림일기만 — HTP 카드는 홈에 없다.
    expect(find.byKey(const ValueKey('activity-9')), findsNothing);
    expect(find.text('집·나무·사람 그림'), findsNothing);
    // 지난 그림 보기·이어 그리기 입구는 새로 그리기 아래 secondary로 상시 노출한다.
    expect(find.byKey(const ValueKey('past-drawings-entry')), findsOneWidget);
    expect(find.text('지난 그림 보기'), findsOneWidget);
    expect(find.byKey(const ValueKey('child-resume-drawing')), findsOneWidget);
    expect(find.text('이어 그리기'), findsOneWidget);
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
    await tester.pump();
    // 가이드가 끝난 일반 변경의 기존 debounce는 정확히 유지한다.
    await tester.pump(const Duration(milliseconds: 599));
    expect(selections, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));

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
    // "끝 → 처음" 순환을 보려면 마지막 코스튬에서 시작해야 한다. 코스튬이 늘어도
    // 전제가 유지되도록 목록의 마지막·첫 항목으로 기대값을 만든다(S15P11B209-866).
    final last = DodamCostume.values.last;
    final first = DodamCostume.values.first;
    final selections = <(int, String)>[];
    await _pumpCarouselHome(
      tester,
      child: _childWith(
        childId: 7,
        nickname: '도담',
        preferredCharacter: last.code,
      ),
      onCharacterSelected: (childId, code) async {
        selections.add((childId, code));
        return true;
      },
    );
    _expectCurrentCostume(tester, last);

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pumpAndSettle();
    _expectCurrentCostume(tester, first);
    await tester.pump(const Duration(milliseconds: 700));

    expect(selections, [(7, first.code)]);
  });

  testWidgets('캐러셀 첫 항목에서 이전은 마지막 친구로 순환하며 endpoint 화살표는 활성이다', (tester) async {
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
    // 첫 항목에서 이전은 목록의 마지막으로 감싸 돈다(S15P11B209-866 이후 PRINCE).
    _expectCurrentCostume(tester, DodamCostume.values.last);

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

    // 코스튬 수보다 많이 눌러야 modulo 순환을 검증한다. 개수를 하드코딩하지 않고
    // 목록 길이에서 계산한다(S15P11B209-866).
    final count = DodamCostume.values.length;
    final taps = count + 2;
    for (var i = 0; i < taps; i++) {
      await tester.tap(find.byKey(const ValueKey('costume-next')));
    }
    await tester.pumpAndSettle();
    final expected = DodamCostume.values[taps % count];
    _expectCurrentCostume(tester, expected);
    await tester.pump(const Duration(milliseconds: 700));

    expect(selections, [expected.code]);
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

    // 코스튬 수보다 많은 prev 뒤에 좌우를 교차한다. 기대값은 시작 index 0에서
    // 실제 이동 횟수를 합산해 계산한다(S15P11B209-866).
    final count = DodamCostume.values.length;
    final prevTaps = count + 1;
    for (var i = 0; i < prevTaps; i++) {
      await tester.tap(find.byKey(const ValueKey('costume-prev')));
    }
    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.tap(find.byKey(const ValueKey('costume-prev')));
    await tester.tap(find.byKey(const ValueKey('costume-prev')));
    await tester.pumpAndSettle();
    final net = -prevTaps + 1 - 2;
    final expected = DodamCostume.values[((net % count) + count) % count];
    _expectCurrentCostume(tester, expected);
    await tester.pump(const Duration(milliseconds: 700));

    expect(selections, [expected.code]);
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

  testWidgets('가이드 완료 사용자의 일반 pending 선택은 dispose에서 정확히 한 번 flush한다', (
    tester,
  ) async {
    final selections = <String>[];
    final save = Completer<bool>();
    await _pumpCarouselHome(
      tester,
      onCharacterSelected: (_, code) {
        selections.add(code);
        return save.future;
      },
    );

    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump(const Duration(milliseconds: 599));
    expect(selections, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(selections, ['PRINCESS']);
    save.complete(true);
    await tester.pump(const Duration(seconds: 1));

    expect(selections, ['PRINCESS']);
    expect(tester.takeException(), isNull);
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

  testWidgets('친구 골라보기는 화살표 탐색 중 저장하지 않고 CTA 저장 성공 뒤에만 완료한다', (tester) async {
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
    await tester.pump(const Duration(seconds: 30));
    expect(patches, isEmpty);
    expect(store.marked, isEmpty);
    _expectCurrentCostume(tester, DodamCostume.princess);
    expect(find.text('공주 도담이로 할래!'), findsOneWidget);
    expect(find.text('마음에 드는 도담이를 골라봐!'), findsOneWidget);
    expect(find.text('더 넘겨봐도 좋아요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
    await tester.pump();
    expect(patches, ['PRINCESS']);
    expect(find.text('친구를 정하고 있어요'), findsOneWidget);
    expect(store.marked, isEmpty);

    save.complete(true);
    await tester.pumpAndSettle();
    expect(store.marked, [7]);
    expect(find.byKey(const ValueKey('child-character-guide')), findsNothing);
    expect(find.text('새 친구와 함께 시작해 볼까?'), findsOneWidget);
  });

  testWidgets('가이드는 이전 화살표와 swipe를 로컬 탐색하고 각각 CTA로 확정한다', (tester) async {
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

    // 첫 항목에서 이전은 목록의 마지막으로 감싸 돈다(S15P11B209-866).
    final wrapped = DodamCostume.values.last;
    await tester.tap(find.byKey(const ValueKey('costume-prev')));
    await tester.pump(const Duration(seconds: 5));
    _expectCurrentCostume(tester, wrapped);
    expect(patches, isEmpty);
    expect(find.text('${wrapped.label}로 할래!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
    await tester.pumpAndSettle();
    expect(patches, [wrapped.code]);
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

    _expectCurrentCostume(tester, DodamCostume.princess);
    expect(patches, isEmpty);
    await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
    await tester.pumpAndSettle();
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
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
    await tester.pumpAndSettle();
    _expectCurrentCostume(tester, DodamCostume.base);
    expect(store.marked, isEmpty);
    expect(find.byKey(const ValueKey('child-character-guide')), findsOneWidget);
    expect(find.text('친구를 정하지 못했어요. 다시 골라볼까요?'), findsWidgets);

    shouldSucceed = true;
    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
    await tester.pumpAndSettle();
    expect(patches, ['PRINCESS', 'PRINCESS']);
    expect(store.marked, [7]);
    _expectCurrentCostume(tester, DodamCostume.princess);
  });

  testWidgets('안내와 가이드의 system back은 현재 진입만 닫고 완료를 저장하지 않는다', (tester) async {
    final store = _FakeIntroStore();
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    final patches = <String>[];
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
          onCharacterSelected: (_, code) async {
            patches.add(code);
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
    await tester.tap(find.byKey(const ValueKey('pick-character-from-intro')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('child-character-guide')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump();
    _expectCurrentCostume(tester, DodamCostume.princess);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('child-character-guide')), findsNothing);
    expect(store.marked, isEmpty);
    expect(patches, isEmpty);
    _expectCurrentCostume(tester, DodamCostume.base);
  });

  testWidgets('가이드 CTA 저장 중 dispose와 이전 child의 늦은 성공은 intro를 완료하지 않는다', (
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
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
    await tester.pump();

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
    expect(find.byKey(const ValueKey('character-guide-confirm')), findsNothing);
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
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
    await tester.pump();

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

  testWidgets('CTA 미확정 선택은 childId 전환 시 PATCH 없이 폐기하고 새 아이 확정값을 쓴다', (
    tester,
  ) async {
    final patches = <(int, String)>[];
    final child = ValueNotifier<ChildSummaryDto>(_child);
    addTearDown(child.dispose);
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
            drawingRepository: _FakeDrawingRepository(
              drawingTypes: const [_artDiary],
            ),
            introStore: _FakeIntroStore(),
            onCharacterSelected: (childId, code) async {
              patches.add((childId, code));
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-character-from-intro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('costume-next')));
    await tester.pump(const Duration(seconds: 5));
    expect(patches, isEmpty);
    _expectCurrentCostume(tester, DodamCostume.princess);

    child.value = otherChild;
    await tester.pumpAndSettle();

    expect(patches, isEmpty);
    _expectCurrentCostume(tester, DodamCostume.dino);
    expect(tester.takeException(), isNull);
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

  testWidgets('active session이 있어도 진입 팝업 없이 이어 그리기 버튼을 노출한다', (
    tester,
  ) async {
    // 안내를 이미 본 아이라 인트로는 뜨지 않는다 — 진입 팝업 제거만 본다.
    final store = _FakeIntroStore(seen: {7});
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

    // 옛 진입 팝업("그리던 그림이 있어요")은 더 이상 뜨지 않는다.
    expect(find.text('그리던 그림이 있어요'), findsNothing);
    // 이어 그리기 버튼은 상시 노출되고, 캔버스로 곧장 열리지도 않는다.
    expect(find.byKey(const ValueKey('child-resume-drawing')), findsOneWidget);
    expect(find.textContaining('drawing-session-'), findsNothing);
    expect(
      find.byKey(const ValueKey('child-character-intro-dialog')),
      findsNothing,
    );
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

  testWidgets('태블릿 가로 폭 양끝(600·1400)에서 홈 본문이 overflow 없이 배치된다', (
    tester,
  ) async {
    // 반응형 상한(ResponsiveContent) 도입 뒤에도 폭 범위 양끝에서 넘침이 없어야
    // 한다(S15P11B209-787). 600은 좁아 narrow 스택, 1400은 wide 본문으로 갈린다.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [Size(600, 900), Size(1400, 900)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(
            child: _child,
            drawingRepository: _FakeDrawingRepository(
              drawingTypes: const [_artDiary],
            ),
            // 안내 팝업을 건너뛰고 홈 본문을 바로 본다.
            introStore: _FakeIntroStore(seen: {_child.childId}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final wide = find.byKey(const ValueKey('child-home-wide-body'));
      final narrow = find.byKey(const ValueKey('child-home-narrow-body'));
      expect(
        wide.evaluate().length + narrow.evaluate().length,
        1,
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

    // 진행 중 활동 확인은 홈 진입 시 한 번만 수행한다. 진입 팝업 없이 이어 그리기
    // 버튼으로 재개한다.
    expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
    expect(find.byKey(const ValueKey('child-resume-drawing')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('child-resume-drawing')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 0);
    expect(
      find.text('drawing-session-321-resume-true-auto-true-fresh-false'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('leave-drawing')));
    await tester.pumpAndSettle();

    // 캔버스에서 뒤로 나오면 활성 세션을 다시 조회해 이어 그리기 대상을 갱신한다.
    expect(repository.getActiveSessionCalls, 2);
    expect(find.byKey(const ValueKey('child-resume-drawing')), findsOneWidget);
    expect(find.text('새로 그리기'), findsOneWidget);
  });

  testWidgets('다른 화면이 홈 위에 있어도 진입 확인은 팝업 없이 안전하다', (tester) async {
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

    // 진입 팝업을 아예 만들지 않으므로 다른 화면 위에 무엇도 덮이지 않고, 캔버스로
    // 자동 진입하지도 않는다. 이어 그리기 대상은 홈에 조용히 보관된다.
    expect(find.text('상단-화면'), findsOneWidget);
    expect(find.text('그리던 그림이 있어요'), findsNothing);
    expect(find.textContaining('drawing-session-'), findsNothing);
    expect(tester.takeException(), isNull);
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
    expect(find.byKey(const ValueKey('child-resume-drawing')), findsOneWidget);
    expect(repository.createCalls, 0);

    await tester.tap(find.byKey(const ValueKey('child-resume-drawing')));
    await tester.pumpAndSettle();

    expect(
      find.text('drawing-session-555-resume-false-auto-true-fresh-false'),
      findsOneWidget,
    );
  });

  testWidgets('진행 중 세션이 있으면 새로 그리기가 그 세션을 대체하고 새 캔버스로 이동한다', (
    tester,
  ) async {
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

    // 이젤 라벨이 "새로 그리기"이고, 진행 중 세션이 있으면 대체(replaceActive)한다.
    expect(find.text('새로 그리기'), findsOneWidget);
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

  testWidgets('이어 그리기 대상이 없으면 빈-상태 팝업을 띄우고 새로 그리기로 잇는다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);
    await tester.pumpWidget(
      _wrap(
        ChildModeHomeScreen(
          child: _child,
          drawingRepository: repository,
          introStore: _FakeIntroStore(seen: {7}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 진행 중 세션이 없으니 이어 그리기 탭은 친근한 빈-상태 팝업을 띄운다.
    await tester.tap(find.byKey(const ValueKey('child-resume-drawing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('resume-empty-dialog')), findsOneWidget);
    expect(find.text('앗, 그리던 그림이 없어요!'), findsOneWidget);
    expect(find.text('새로 그려볼까요?'), findsOneWidget);
    expect(repository.createCalls, 0);

    // 닫기는 세션을 만들지 않고 홈에 남는다.
    await tester.tap(find.byKey(const ValueKey('resume-empty-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('resume-empty-dialog')), findsNothing);
    expect(repository.createCalls, 0);

    // 다시 열어 "새로 그리기"를 누르면 그림일기 안내로 이어지고, 대체 없이 시작한다.
    await tester.tap(find.byKey(const ValueKey('child-resume-drawing')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resume-empty-start-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('resume-empty-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('activity-guide-start')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('activity-guide-start')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 1);
    expect(repository.lastCreateRequest?.replaceActive, isFalse);
    expect(
      find.text('drawing-session-900-resume-false-auto-false-fresh-true'),
      findsOneWidget,
    );
  });

  group('HTP 재진입 복구', () {
    Future<void> resumeActive(WidgetTester tester) async {
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('child-resume-drawing')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('child-resume-drawing')));
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

  // ── S15P11B209-850 Spotlight ─────────────────────────────────────────
  //
  // S863: 가이드 탐색은 로컬 미리보기이며 명시적 CTA만 PATCH한다. 가이드가
  // 끝난 일반 캐릭터 변경의 600ms debounce는 위 회귀 테스트에서 유지한다.
  group('캐릭터 선택 Spotlight', () {
    const spotlight = ValueKey('character-carousel-spotlight');
    const scrim = ValueKey('character-spotlight-scrim');
    const ring = ValueKey('character-spotlight-ring');
    const coach = ValueKey('character-spotlight-coach');
    const guideKey = ValueKey('child-character-guide');

    /// subpixel 오차만 허용하는 rect 비교.
    bool rectNearlyEquals(Rect a, Rect b, double epsilon) =>
        (a.left - b.left).abs() <= epsilon &&
        (a.top - b.top).abs() <= epsilon &&
        (a.right - b.right).abs() <= epsilon &&
        (a.bottom - b.bottom).abs() <= epsilon;

    /// 캐러셀이 자동 스크롤을 마치고 **위치가 안정될 때까지** 제한적으로 pump한다.
    ///
    /// 유한 pulse가 계속 frame을 예약하므로 `pumpAndSettle`에 의존할 수 없고,
    /// 고정 sleep은 기기·레이아웃에 따라 깨진다. 연속 두 표본이 epsilon 이내로
    /// 같아지면 안정으로 보고, 그 뒤 한 frame을 더 흘려 ScrollEnd가 예약한
    /// spotlight 재측정까지 반영한다.
    Future<Rect> waitForStableCarouselRect(
      WidgetTester tester, {
      Duration step = const Duration(milliseconds: 100),
      int maxSteps = 30,
      double epsilon = 0.5,
    }) async {
      final carousel = find.byKey(const ValueKey('costume-carousel'));
      final history = <Rect>[];
      Rect? previous;
      var stableSamples = 0;

      for (var index = 0; index < maxSteps; index++) {
        await tester.pump(step);
        final current = tester.getRect(carousel);
        history.add(current);

        if (previous != null && rectNearlyEquals(previous, current, epsilon)) {
          stableSamples++;
          if (stableSamples >= 2) {
            // ScrollEnd 이후 예약된 재측정이 반영되도록 한 frame 더.
            await tester.pump();
            return tester.getRect(carousel);
          }
        } else {
          stableSamples = 0;
        }
        previous = current;
      }

      fail('캐러셀 rect가 안정화되지 않음: $history');
    }

    Rect holeOf(WidgetTester tester) {
      final widget = tester.widget<CharacterCarouselSpotlight>(
        find.byKey(spotlight),
      );
      final rect = widget.targetRect!;
      return Rect.fromLTRB(
        rect.left - CharacterCarouselSpotlight.holePadding,
        rect.top - CharacterCarouselSpotlight.holePadding,
        rect.right + CharacterCarouselSpotlight.holePadding,
        rect.bottom + CharacterCarouselSpotlight.holePadding,
      );
    }

    /// 안내 팝업에서 `친구 골라보기`를 눌러 spotlight 단계까지 들어간다.
    Future<_FakeIntroStore> enterSpotlight(
      WidgetTester tester, {
      Future<bool> Function(int childId, String code)? onCharacterSelected,
      Size size = const Size(390, 844),
      double textScale = 1,
      bool disableAnimations = false,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = _FakeIntroStore();
      // MediaQuery를 MaterialApp 바깥에 두면 MaterialApp이 view 기준으로 자체
      // MediaQuery를 다시 삽입해 무효가 된다. 기존 S843 하네스와 같은 트리를
      // 유지하기 위해 화면 바로 위(home 하위)에서 덮어쓴다.
      await tester.pumpWidget(
        _wrap(
          MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: ChildModeHomeScreen(
              child: _child,
              drawingRepository: _FakeDrawingRepository(
                drawingTypes: const [_secondType, _artDiary],
              ),
              introStore: store,
              onCharacterSelected: onCharacterSelected,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 좁은 화면·큰 글자에서는 안내 팝업 본문이 스크롤된다. 기존 S843 하네스와
      // 같이 버튼을 화면에 올린 뒤 눌러야 탭이 빗나가지 않는다.
      final pick = find.byKey(const ValueKey('pick-character-from-intro'));
      await tester.ensureVisible(pick);
      await tester.pump();
      await tester.tap(pick);
      // 안내 팝업이 닫혔는지는 다이얼로그 자체로 확인한다. `ModalBarrier`는 home
      // route가 항상 만드는 투명·비차단 barrier까지 잡혀 신호로 쓸 수 없다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const ValueKey('child-character-intro-dialog')),
        findsNothing,
      );
      // 안내 진입은 포커스 요청과 ensureVisible로 캐러셀을 화면에 올린다. 그
      // 자동 스크롤이 끝나기 전에 단정·탭하면 좌표가 어긋나므로, 시간이 아니라
      // **위치가 안정될 때까지** 기다린다.
      await waitForStableCarouselRect(tester);
      return store;
    }

    bool holeContains(Rect hole, Rect rect) =>
        hole.left <= rect.left &&
        hole.top <= rect.top &&
        hole.right >= rect.right &&
        hole.bottom >= rect.bottom;

    /// 캐러셀 위치가 안정되고 화살표가 hole 안에 있음을 확인한 뒤 실제로 누른다.
    ///
    /// 좌표를 임의로 만들지 않고 production finder와 실제 tap을 그대로 쓴다.
    /// hole 밖이면 barrier에 막히는 상태이므로 조용히 넘기지 않고 실패시킨다.
    Future<void> tapArrow(WidgetTester tester, Key arrowKey) async {
      // 다른 요소로 스크롤했다면 화살표가 viewport 밖일 수 있다. 사용자와 같은
      // 방식으로 다시 화면에 올린 뒤 위치가 안정될 때까지 기다린다.
      await tester.ensureVisible(find.byKey(arrowKey));
      await tester.pump();
      await waitForStableCarouselRect(tester);
      // 캐러셀이 멈춘 뒤에도 production의 ScrollEnd 재측정이 한 frame 늦게
      // 반영될 수 있다. hole이 화살표를 품을 때까지 제한적으로 기다린다.
      var hole = holeOf(tester);
      var arrow = tester.getRect(find.byKey(arrowKey));
      final history = <String>[];
      for (var i = 0; i < 10 && !hole.contains(arrow.center); i++) {
        history.add('hole=$hole arrow=${arrow.center}');
        await tester.pump(const Duration(milliseconds: 100));
        hole = holeOf(tester);
        arrow = tester.getRect(find.byKey(arrowKey));
      }
      expect(
        hole.contains(arrow.center),
        isTrue,
        reason: '화살표 중심이 spotlight hole 밖이다: $arrow vs $hole (이력: $history)',
      );
      await tester.tap(find.byKey(arrowKey));
    }

    testWidgets('scrim·hole·흰 outline·노란 ring·코치마크가 함께 나타난다', (tester) async {
      final patches = <String>[];
      await enterSpotlight(
        tester,
        onCharacterSelected: (_, code) async {
          patches.add(code);
          return true;
        },
      );

      expect(find.byKey(spotlight), findsOneWidget);
      expect(find.byKey(coach), findsOneWidget);
      expect(find.text('화살표를 눌러 함께할 도담이를 골라봐!'), findsOneWidget);
      expect(find.text('좌우로 넘겨볼 수도 있어요'), findsOneWidget);
      // 실제 선택 변경 전에는 완료 CTA가 없다.
      expect(
        find.byKey(const ValueKey('character-guide-confirm')),
        findsNothing,
      );
      expect(find.text('선택한 친구를 저장하고 있어요'), findsNothing);
      expect(patches, isEmpty);

      final scrimPainter =
          tester.widget<CustomPaint>(find.byKey(scrim)).painter!
              as SpotlightScrimPainter;
      expect(scrimPainter.hole, holeOf(tester));
      expect(scrimPainter.radius, CharacterCarouselSpotlight.holeRadius);
      final ringPainter =
          tester.widget<CustomPaint>(find.byKey(ring)).painter!
              as SpotlightPulseRingPainter;
      expect(ringPainter.color, AppColors.sunshine);
      expect(tester.takeException(), isNull);
    });

    testWidgets('spotlight hole이 실제 캐러셀 전체를 감싸고 복제하지 않는다', (tester) async {
      await enterSpotlight(tester);

      final hole = holeOf(tester);
      for (final target in [
        find.byKey(const ValueKey('costume-carousel')),
        find.byKey(const ValueKey('costume-prev')),
        find.byKey(const ValueKey('costume-next')),
        find.byKey(const ValueKey('costume-indicator-BASE')),
      ]) {
        expect(
          holeContains(hole, tester.getRect(target)),
          isTrue,
          reason: 'spotlight 밖에 있다: ${tester.getRect(target)} vs $hole',
        );
      }
      expect(hole.isEmpty, isFalse);
      // 캐러셀은 하나만 존재한다(오버레이가 복제하지 않는다).
      expect(find.byKey(const ValueKey('costume-carousel')), findsOneWidget);
      expect(find.byKey(const ValueKey('costume-prev')), findsOneWidget);
    });

    testWidgets('다음 tap 후 30초 동안 PATCH하지 않고 CTA tap만 최신 선택을 저장한다', (
      tester,
    ) async {
      final patches = <String>[];
      final save = Completer<bool>();
      final store = await enterSpotlight(
        tester,
        onCharacterSelected: (_, code) {
          patches.add(code);
          return save.future;
        },
      );

      await tester.tap(find.byKey(const ValueKey('costume-next')));
      await tester.pump();

      expect(find.text('마음에 드는 도담이를 골라봐!'), findsOneWidget);
      expect(find.text('더 넘겨봐도 좋아요'), findsOneWidget);
      expect(find.text('공주 도담이로 할래!'), findsOneWidget);
      _expectCurrentCostume(tester, DodamCostume.princess);

      // 가이드에서는 599ms·600ms·5초·30초 어느 시점에도 자동 저장하지 않는다.
      await tester.pump(const Duration(milliseconds: 599));
      expect(patches, isEmpty);
      expect(store.marked, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(patches, isEmpty);
      await tester.pump(const Duration(milliseconds: 4400));
      expect(patches, isEmpty);
      await tester.pump(const Duration(seconds: 25));
      expect(patches, isEmpty);
      expect(find.byKey(spotlight), findsOneWidget);
      expect(find.text('친구를 정하고 있어요'), findsNothing);

      final confirm = find.byKey(const ValueKey('character-guide-confirm'));
      expect(tester.getSize(confirm).height, greaterThanOrEqualTo(48));
      final semantics = tester.getSemantics(confirm);
      expect(semantics.label, contains('공주 도담이'));
      expect(semantics.flagsCollection.isButton, isTrue);

      final center = tester.getCenter(confirm);
      final firstTap = await tester.startGesture(center, pointer: 1);
      final secondTap = await tester.startGesture(center, pointer: 2);
      await firstTap.up();
      await secondTap.up();
      await tester.pump();
      expect(patches, ['PRINCESS']);
      expect(find.text('친구를 정하고 있어요'), findsOneWidget);
      expect(find.text('선택한 친구를 저장하고 있어요'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      // PATCH 성공 전에는 안내를 완료하지 않는다.
      expect(store.marked, isEmpty);
      expect(find.byKey(spotlight), findsOneWidget);

      save.complete(true);
      await tester.pumpAndSettle();
      expect(store.marked, [7]);
      expect(find.byKey(spotlight), findsNothing);
      expect(find.byKey(guideKey), findsNothing);
      expect(find.text('새 친구와 함께 시작해 볼까?'), findsOneWidget);
    });

    testWidgets('CTA 저장 중에는 화살표·swipe·중복 CTA를 막고 활동이나 navigation을 시작하지 않는다', (
      tester,
    ) async {
      final patches = <String>[];
      final save = Completer<bool>();
      final store = await enterSpotlight(
        tester,
        onCharacterSelected: (_, code) {
          patches.add(code);
          return save.future;
        },
      );

      await tester.tap(find.byKey(const ValueKey('costume-next')));
      await tester.pump();
      final confirm = find.byKey(const ValueKey('character-guide-confirm'));
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.tap(find.byKey(const ValueKey('costume-next')));
      await tester.drag(
        find.byKey(const ValueKey('costume-carousel')),
        const Offset(-400, 0),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(patches, ['PRINCESS']);
      _expectCurrentCostume(tester, DodamCostume.princess);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('costume-next')))
            .flagsCollection
            .isEnabled,
        ui.Tristate.isFalse,
      );
      expect(store.marked, isEmpty);
      expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
      expect(find.byType(ChildModeHomeScreen), findsOneWidget);

      save.complete(true);
      await tester.pumpAndSettle();
      expect(store.marked, [7]);
      expect(patches, ['PRINCESS']);
    });

    testWidgets('이전 화살표 실제 tap도 로컬 탐색 후 CTA로 확정한다', (tester) async {
      final patches = <String>[];
      await enterSpotlight(
        tester,
        onCharacterSelected: (_, code) async {
          patches.add(code);
          return true;
        },
      );

      // 첫 항목에서 이전은 목록의 마지막으로 감싸 돈다(S15P11B209-866).
      final wrapped = DodamCostume.values.last;
      await tester.tap(find.byKey(const ValueKey('costume-prev')));
      await tester.pump();

      expect(find.text('마음에 드는 도담이를 골라봐!'), findsOneWidget);
      _expectCurrentCostume(tester, wrapped);
      await tester.pump(const Duration(seconds: 5));
      expect(patches, isEmpty);

      await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
      await tester.pumpAndSettle();
      expect(patches, [wrapped.code]);
    });

    testWidgets('swipe 실제 동작도 조작으로 인정한다', (tester) async {
      final patches = <String>[];
      await enterSpotlight(
        tester,
        onCharacterSelected: (_, code) async {
          patches.add(code);
          return true;
        },
      );

      await tester.drag(
        find.byKey(const ValueKey('costume-carousel')),
        const Offset(-400, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('마음에 드는 도담이를 골라봐!'), findsOneWidget);
      expect(patches, isEmpty);

      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(patches, isEmpty);
      await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
      await tester.pumpAndSettle();
      expect(patches, hasLength(1));
    });

    testWidgets('빠른 연속 조작은 중간값을 저장하지 않고 CTA가 마지막 선택만 PATCH한다', (tester) async {
      final patches = <String>[];
      await enterSpotlight(
        tester,
        onCharacterSelected: (_, code) async {
          patches.add(code);
          return true;
        },
      );

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('costume-next')));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(patches, isEmpty);

      await tester.pump(const Duration(seconds: 5));
      expect(patches, isEmpty);
      expect(find.text('${DodamCostume.values[3].label}로 할래!'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
      await tester.pumpAndSettle();
      expect(patches, hasLength(1));
      expect(patches.single, DodamCostume.values[3].code);
    });

    testWidgets('저장 실패는 rollback하고 spotlight를 유지하며 다시 조작할 수 있다', (
      tester,
    ) async {
      final patches = <String>[];
      var fail = true;
      final store = await enterSpotlight(
        tester,
        onCharacterSelected: (_, code) async {
          patches.add(code);
          return !fail;
        },
      );

      await tester.tap(find.byKey(const ValueKey('costume-next')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
      await tester.pumpAndSettle();

      expect(patches, ['PRINCESS']);
      expect(store.marked, isEmpty);
      expect(find.byKey(spotlight), findsOneWidget);
      expect(find.text('친구를 정하지 못했어요. 다시 골라볼까요?'), findsWidgets);
      _expectCurrentCostume(tester, DodamCostume.base);

      // 실패 코치마크가 캐러셀을 가리거나 입력을 막지 않는다.
      final hole = holeOf(tester);
      expect(hole.overlaps(tester.getRect(find.byKey(coach))), isFalse);

      fail = false;
      await tester.tap(find.byKey(const ValueKey('costume-next')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
      await tester.pumpAndSettle();
      expect(patches, ['PRINCESS', 'PRINCESS']);
      expect(store.marked, [7]);
      expect(find.byKey(spotlight), findsNothing);
    });

    testWidgets('spotlight 밖 배경 CTA는 막고 안쪽 캐러셀 입력은 통과한다', (tester) async {
      // 스크롤 없이 배경 CTA와 캐러셀이 함께 보이는 넓은 화면에서 본다. 스크롤로
      // 위치를 흔들면 무엇이 막혔는지가 아니라 좌표 문제가 섞인다.
      final store = await enterSpotlight(
        tester,
        size: const Size(1600, 1000),
        onCharacterSelected: (_, _) async => true,
      );

      final drawEntry = find.byKey(const ValueKey('draw-entry'));
      expect(drawEntry, findsOneWidget);
      final hole = holeOf(tester);
      final entryRect = tester.getRect(drawEntry);
      // 전제: 배경 CTA는 spotlight 바깥에 있다.
      expect(hole.overlaps(entryRect), isFalse);

      await tester.tap(drawEntry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // barrier가 흡수했으므로 활동 안내 팝업도, 세션 생성도 일어나지 않는다.
      expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
      expect(find.byKey(spotlight), findsOneWidget);
      expect(store.marked, isEmpty);

      // 반면 hole 안쪽 실제 화살표는 그대로 동작한다.
      await tapArrow(tester, const ValueKey('costume-next'));
      await tester.pump();
      expect(find.text('마음에 드는 도담이를 골라봐!'), findsOneWidget);
      _expectCurrentCostume(tester, DodamCostume.princess);
    });

    testWidgets('지금 도담이로 시작할래는 spotlight와 PATCH 없이 기존 동작을 유지한다', (
      tester,
    ) async {
      final patches = <String>[];
      final store = _FakeIntroStore();
      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(
            child: _child,
            drawingRepository: _FakeDrawingRepository(
              drawingTypes: const [_secondType, _artDiary],
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
      await tester.tap(find.byKey(const ValueKey('choose-character-later')));
      await tester.pumpAndSettle();

      expect(find.byKey(spotlight), findsNothing);
      expect(find.byKey(scrim), findsNothing);
      expect(patches, isEmpty);
      expect(store.marked, [7]);
    });

    testWidgets('active session이 있어도 진입 팝업 없이 최초 캐릭터 안내를 띄운다', (
      tester,
    ) async {
      // 진입 팝업을 없앤 뒤에는 홈에 머물므로, 안내를 못 본 아이에게는 인트로가
      // 그대로 뜬다. 이어 그리기 대상은 버튼 뒤에 조용히 보관된다(S15P11B209-916).
      final store = _FakeIntroStore();
      await tester.pumpWidget(
        _wrap(
          ChildModeHomeScreen(
            child: _child,
            drawingRepository: _FakeDrawingRepository(
              drawingTypes: const [_secondType, _artDiary],
              activeSession: const ActiveDrawingSessionDto(
                drawingSessionId: 41,
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
            ),
            introStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 옛 진입 팝업은 사라지고 인트로가 뜬다. spotlight는 아직 고르기 전이라 없다.
      expect(find.text('그리던 그림이 있어요'), findsNothing);
      expect(
        find.byKey(const ValueKey('child-character-intro-dialog')),
        findsOneWidget,
      );
      expect(find.byKey(spotlight), findsNothing);
      expect(store.marked, isEmpty);
      // 캔버스로 자동 진입하지 않는다.
      expect(find.textContaining('drawing-session-'), findsNothing);
    });

    testWidgets('같은 아이로 rebuild해도 조작 상태가 초기화되지 않는다', (tester) async {
      await enterSpotlight(tester, onCharacterSelected: (_, _) async => true);
      await tapArrow(tester, const ValueKey('costume-next'));
      await tester.pump();
      expect(find.text('마음에 드는 도담이를 골라봐!'), findsOneWidget);
      expect(find.text('공주 도담이로 할래!'), findsOneWidget);

      await tester.pump();
      expect(find.byKey(spotlight), findsOneWidget);
      expect(find.text('마음에 드는 도담이를 골라봐!'), findsOneWidget);
      expect(find.text('공주 도담이로 할래!'), findsOneWidget);
    });

    testWidgets('화면 크기가 바뀌면 AnimatedScale까지 반영해 rect를 다시 잰다', (tester) async {
      await enterSpotlight(tester);
      final before = holeOf(tester);

      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();

      final after = holeOf(tester);
      expect(after, isNot(before));
      expect(
        holeContains(
          after,
          tester.getRect(find.byKey(const ValueKey('costume-carousel'))),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('동일 rect가 유지되면 추가 setState로 rebuild하지 않는다', (tester) async {
      await enterSpotlight(tester);
      final first = holeOf(tester);

      // 크기 변화 없이 여러 frame을 흘려도 rect가 그대로다.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(holeOf(tester), first);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CTA 저장 도중 dispose되어도 늦은 성공이 예외를 만들지 않는다', (tester) async {
      final save = Completer<bool>();
      final store = await enterSpotlight(
        tester,
        onCharacterSelected: (_, _) => save.future,
      );

      await tester.tap(find.byKey(const ValueKey('costume-next')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      save.complete(true);
      await tester.pumpAndSettle();

      expect(store.marked, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CTA를 누르지 않은 선택은 dispose해도 PATCH하지 않고 예외가 없다', (tester) async {
      final patches = <String>[];
      final store = await enterSpotlight(
        tester,
        onCharacterSelected: (_, code) async {
          patches.add(code);
          return true;
        },
      );

      await tapArrow(tester, const ValueKey('costume-next'));
      await tester.pump();
      expect(patches, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));

      expect(patches, isEmpty);
      expect(tester.takeException(), isNull);
      expect(store.marked, isEmpty);
    });

    testWidgets('CTA 요청의 dispose 이후 실패도 rollback setState 없이 조용히 끝난다', (
      tester,
    ) async {
      final patches = <String>[];
      final save = Completer<bool>();
      final store = await enterSpotlight(
        tester,
        onCharacterSelected: (_, code) {
          patches.add(code);
          return save.future;
        },
      );

      await tapArrow(tester, const ValueKey('costume-next'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(patches, ['PRINCESS']);

      save.complete(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(patches, ['PRINCESS']);
      expect(store.marked, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CTA 요청 중 system back 뒤 늦은 실패가 spotlight를 되살리지 않는다', (
      tester,
    ) async {
      final save = Completer<bool>();
      final store = await enterSpotlight(
        tester,
        onCharacterSelected: (_, _) => save.future,
      );

      await tapArrow(tester, const ValueKey('costume-next'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('character-guide-confirm')));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(spotlight), findsNothing);

      save.complete(false);
      await tester.pumpAndSettle();

      expect(find.byKey(spotlight), findsNothing);
      expect(store.marked, isEmpty);
      expect(find.text('친구를 정하지 못했어요. 다시 골라볼까요?'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('조작 없이 화면을 떠나면 PATCH를 만들지 않는다', (tester) async {
      final patches = <String>[];
      final store = await enterSpotlight(
        tester,
        onCharacterSelected: (_, code) async {
          patches.add(code);
          return true;
        },
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 800));

      expect(patches, isEmpty);
      expect(store.marked, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disableAnimations에서는 처음부터 정적 강조로 표시한다', (tester) async {
      await enterSpotlight(tester, disableAnimations: true);

      expect(find.byKey(scrim), findsOneWidget);
      expect(find.byKey(coach), findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(find.byKey(ring)).painter!
              as SpotlightPulseRingPainter;
      expect(painter.animating, isFalse);
      expect(painter.progress, 0);
      // 정적 강조라도 spotlight 자체는 사라지지 않는다.
      expect(find.byKey(spotlight), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('유한 pulse가 끝나도 spotlight와 안내는 유지된다', (tester) async {
      await enterSpotlight(tester);

      // 6회(1400ms×6)를 넉넉히 넘겨도 안내가 사라지지 않는다.
      await tester.pump(const Duration(seconds: 12));

      expect(find.byKey(spotlight), findsOneWidget);
      expect(find.byKey(coach), findsOneWidget);
      expect(find.text('화살표를 눌러 함께할 도담이를 골라봐!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final layout in const <({String label, Size size, double scale})>[
      (label: '320x640', size: Size(320, 640), scale: 1),
      (label: '390x844', size: Size(390, 844), scale: 1),
      (label: '휴대폰 가로 844x390', size: Size(844, 390), scale: 1),
      (label: 'Pixel Tablet 가로 1600x1000', size: Size(1600, 1000), scale: 1),
      (label: '태블릿 세로 800x1280', size: Size(800, 1280), scale: 1),
      (label: '태블릿 가로 1280x800', size: Size(1280, 800), scale: 1),
      (label: 'text scale 2.0', size: Size(390, 844), scale: 2),
      (label: '휴대폰 가로 844x390 + textScale 2.0', size: Size(844, 390), scale: 2),
    ]) {
      testWidgets('${layout.label}에서 spotlight가 overflow 없이 배치된다', (
        tester,
      ) async {
        await enterSpotlight(
          tester,
          size: layout.size,
          textScale: layout.scale,
          onCharacterSelected: (_, _) async => true,
        );

        expect(find.byKey(scrim), findsOneWidget);
        expect(find.byKey(coach), findsOneWidget);
        final hole = holeOf(tester);
        expect(
          holeContains(
            hole,
            tester.getRect(find.byKey(const ValueKey('costume-carousel'))),
          ),
          isTrue,
        );

        // 코치마크는 화면 안에 놓이고, 겹치더라도 캐러셀 입력을 막지 않는다.
        final coachRect = tester.getRect(find.byKey(coach));
        expect(coachRect.top, greaterThanOrEqualTo(0));
        expect(
          coachRect.bottom,
          lessThanOrEqualTo(tester.view.physicalSize.height),
        );

        for (final arrow in [
          const ValueKey('costume-prev'),
          const ValueKey('costume-next'),
        ]) {
          expect(
            tester.getSize(find.byKey(arrow)).height,
            greaterThanOrEqualTo(48),
          );
        }

        // 실제 화살표 조작 뒤 나타나는 CTA도 SafeArea 안에 있고 캐러셀 입력을
        // 덮지 않으며, 현재 캐릭터 이름을 semantics로 제공한다.
        await tapArrow(tester, const ValueKey('costume-next'));
        await tester.pump(const Duration(milliseconds: 200));
        final confirm = find.byKey(const ValueKey('character-guide-confirm'));
        expect(confirm, findsOneWidget);
        expect(tester.getSize(confirm).height, greaterThanOrEqualTo(48));
        final confirmRect = tester.getRect(confirm);
        expect(confirmRect.top, greaterThanOrEqualTo(0));
        expect(
          confirmRect.bottom,
          lessThanOrEqualTo(tester.view.physicalSize.height),
        );
        expect(
          confirmRect.overlaps(
            tester.getRect(find.byKey(const ValueKey('costume-prev'))),
          ),
          isFalse,
        );
        expect(
          confirmRect.overlaps(
            tester.getRect(find.byKey(const ValueKey('costume-next'))),
          ),
          isFalse,
        );
        expect(tester.getSemantics(confirm).label, contains('공주 도담이'));
        await tester.tap(confirm);
        await tester.pumpAndSettle();

        // 제약에 맞는 layout이 선택됐는지 key로 확정한다.
        final wide = find.byKey(const ValueKey('child-home-wide-body'));
        final narrow = find.byKey(const ValueKey('child-home-narrow-body'));
        expect(wide.evaluate().length + narrow.evaluate().length, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('코치마크는 liveRegion으로 안내하고 장식은 중복 낭독하지 않는다', (tester) async {
      await enterSpotlight(tester);

      final semantics = tester.getSemantics(find.byKey(guideKey));
      expect(semantics.label, contains('화살표를 눌러 함께할 도담이를 골라봐!'));
      expect(semantics.label, contains('좌우로 넘겨볼 수도 있어요'));
      // 실제 조작 대상은 캐러셀 화살표 하나뿐이다.
      expect(find.bySemanticsLabel('이전 친구'), findsOneWidget);
      expect(find.bySemanticsLabel('다음 친구'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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
