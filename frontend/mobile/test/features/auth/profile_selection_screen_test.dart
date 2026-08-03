import 'dart:async';
import 'dart:ui' as ui;

import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('보호자와 아이 카드형 레이아웃 및 production asset을 렌더링한다', (tester) async {
    final controller = await _loadedController([
      _child(id: 3, nickname: '하늘', age: 6),
      _child(id: 7, nickname: '바다', age: 8),
    ]);
    addTearDown(controller.dispose);

    await _pumpScreen(tester, controller: controller);

    expect(find.text('안녕하세요! 누구로 시작할까요?'), findsOneWidget);
    expect(find.text('보호자 모드'), findsOneWidget);
    expect(find.text('보호자로 시작하기'), findsOneWidget);
    expect(find.text('아이 모드'), findsOneWidget);
    expect(find.text('아이로 시작하기'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-role-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('child-role-card')), findsOneWidget);

    final guardian = tester.widget<Image>(
      find.byKey(const ValueKey('guardian-dodami-image')),
    );
    final child = tester.widget<Image>(
      find.byKey(const ValueKey('child-dodami-image')),
    );
    expect(
      (guardian.image as AssetImage).assetName,
      'assets/images/role_selection/guardian_dodami.png',
    );
    expect(guardian.fit, BoxFit.contain);
    expect(
      (child.image as AssetImage).assetName,
      'assets/images/role_selection/child_dodami.png',
    );
    expect(child.fit, BoxFit.contain);

    final context = tester.element(find.byType(ProfileSelectionScreen));
    for (final asset in [
      'assets/images/role_selection/guardian_dodami.png',
      'assets/images/role_selection/child_dodami.png',
    ]) {
      final bytes = await DefaultAssetBundle.of(context).load(asset);
      expect(bytes.lengthInBytes, greaterThan(0), reason: asset);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('보호자 카드를 연속 탭해도 callback은 한 번이다', (tester) async {
    final controller = await _loadedController([_child(id: 3)]);
    addTearDown(controller.dispose);
    var calls = 0;
    await _pumpScreen(
      tester,
      controller: controller,
      onGuardianSelected: (_) => calls += 1,
    );

    final guardian = find.byKey(const ValueKey('guardian-profile'));
    await tester.tap(guardian);
    await tester.tap(guardian);

    expect(calls, 1);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('guardian-start-cta')))
          .shortestSide,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('아이 프로필 연속 탭은 정확한 childId를 한 번만 전달한다', (tester) async {
    final controller = await _loadedController([_child(id: 3), _child(id: 17)]);
    addTearDown(controller.dispose);
    final selectedIds = <int>[];
    await _pumpScreen(
      tester,
      controller: controller,
      onChildSelected: (_, child) => selectedIds.add(child.childId),
    );

    final profile = find.byKey(const ValueKey('child-profile-17'));
    await tester.ensureVisible(profile);
    await tester.tap(profile);
    await tester.tap(profile);

    expect(selectedIds, [17]);
    expect(tester.getSize(profile).shortestSide, greaterThanOrEqualTo(48));
  });

  testWidgets('실제 이름과 나이를 표시하고 나이가 유효하지 않으면 이름만 표시한다', (tester) async {
    final controller = await _loadedController([
      _child(id: 3, nickname: '하늘', age: 6),
      _child(id: 7, nickname: '바다', age: 8),
      _child(id: 9, nickname: '별', age: 0),
    ]);
    addTearDown(controller.dispose);
    await _pumpScreen(tester, controller: controller);

    expect(find.text('하늘 · 6세'), findsOneWidget);
    expect(find.text('바다 · 8세'), findsOneWidget);
    expect(find.text('별'), findsOneWidget);
    expect(find.text('별 · 0세'), findsNothing);
    expect(find.textContaining('null세'), findsNothing);
  });

  testWidgets('긴 이름은 말줄임 처리되고 overflow가 발생하지 않는다', (tester) async {
    final controller = await _loadedController([
      _child(id: 3, nickname: '아주아주긴아이프로필이름입니다', age: 6),
    ]);
    addTearDown(controller.dispose);
    await _pumpScreen(
      tester,
      controller: controller,
      size: const Size(320, 640),
      textScale: 2,
    );

    final label = tester.widget<Text>(find.textContaining('아주아주긴아이'));
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('아이가 없으면 빈 프로필 없이 추가 버튼만 표시하고 callback을 실행한다', (tester) async {
    final controller = await _loadedController(const []);
    addTearDown(controller.dispose);
    var additions = 0;
    await _pumpScreen(
      tester,
      controller: controller,
      onAddChild: (_) => additions += 1,
    );

    expect(find.byKey(const ValueKey('child-profile-carousel')), findsNothing);
    expect(find.byKey(const ValueKey('add-child-profile')), findsOneWidget);
    expect(find.text('추가'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-child-profile')));
    expect(additions, 1);
  });

  testWidgets('아이 한 명과 추가 버튼을 함께 표시한다', (tester) async {
    final controller = await _loadedController([_child(id: 3)]);
    addTearDown(controller.dispose);
    await _pumpScreen(tester, controller: controller);

    expect(find.byKey(const ValueKey('child-profile-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-child-profile')), findsOneWidget);
  });

  testWidgets('아이 다수는 가로 스크롤해 마지막 프로필과 추가 버튼에 접근한다', (tester) async {
    final children = List.generate(
      8,
      (index) => _child(id: index + 1, nickname: '아이 ${index + 1}'),
    );
    final controller = await _loadedController(children);
    addTearDown(controller.dispose);
    var additions = 0;
    await _pumpScreen(
      tester,
      controller: controller,
      size: const Size(600, 800),
      onAddChild: (_) => additions += 1,
    );

    final carousel = find.byKey(const ValueKey('child-profile-carousel'));
    await tester.ensureVisible(carousel);
    await tester.pump();
    final horizontalScrollable = find
        .descendant(of: carousel, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('child-profile-8')),
      300,
      scrollable: horizontalScrollable,
    );
    expect(find.byKey(const ValueKey('child-profile-8')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('add-child-profile')),
      300,
      scrollable: horizontalScrollable,
    );
    await tester.tap(find.byKey(const ValueKey('add-child-profile')));
    expect(additions, 1);
  });

  testWidgets('설정에서 프로필 편집과 기존 로그아웃 action에 접근한다', (tester) async {
    final controller = await _loadedController([_child(id: 3)]);
    addTearDown(controller.dispose);
    var editedChildId = 0;
    var logoutCalls = 0;
    await _pumpScreen(
      tester,
      controller: controller,
      onEditChild: (_, child) => editedChildId = child.childId,
      headerAction: IconButton(
        key: const ValueKey('logout-action'),
        onPressed: () => logoutCalls += 1,
        icon: const Icon(Icons.logout_rounded),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('profile-selection-settings')));
    await tester.pumpAndSettle();
    expect(find.text('프로필 편집'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('edit-child-profiles')));
    await tester.pumpAndSettle();
    expect(find.text('수정하거나 삭제할 아이를 선택해 주세요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('child-profile-3')));
    expect(editedChildId, 3);

    await tester.tap(find.byKey(const ValueKey('profile-selection-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logout-action')));
    expect(logoutCalls, 1);
  });

  testWidgets('설정 메뉴는 기존 전체 설정 callback을 재사용한다', (tester) async {
    final controller = await _loadedController([_child(id: 3)]);
    addTearDown(controller.dispose);
    var settingsCalls = 0;
    await _pumpScreen(
      tester,
      controller: controller,
      onSettings: (_) => settingsCalls += 1,
    );

    await tester.tap(find.byKey(const ValueKey('profile-selection-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-guardian-settings')));
    await tester.pumpAndSettle();

    expect(settingsCalls, 1);
  });

  testWidgets('loading 중에는 보호자·아이 navigation을 실행하지 않는다', (tester) async {
    final pending = Completer<List<ChildSummaryDto>>();
    final repository = _FakeChildRepository(pending: pending);
    final controller = GuardianChildController(repository);
    addTearDown(controller.dispose);
    final load = controller.loadChildren();
    var guardianCalls = 0;
    var childCalls = 0;
    await _pumpScreen(
      tester,
      controller: controller,
      onGuardianSelected: (_) => guardianCalls += 1,
      onChildSelected: (_, _) => childCalls += 1,
    );

    expect(find.text('아이 프로필을 불러오고 있어요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guardian-profile')));
    expect(guardianCalls, 0);
    expect(childCalls, 0);

    pending.complete([_child(id: 3)]);
    await load;
    await tester.pump();
  });

  testWidgets('error의 기존 재시도로 목록을 중복 없이 다시 표시한다', (tester) async {
    final repository = _FakeChildRepository(error: StateError('network'));
    final controller = GuardianChildController(repository);
    addTearDown(controller.dispose);
    await controller.loadChildren();
    await _pumpScreen(tester, controller: controller);

    expect(find.text('아이 프로필을 불러오지 못했어요'), findsOneWidget);
    repository
      ..error = null
      ..children = [_child(id: 3), _child(id: 7)];
    final retry = find.text('다시 시도');
    await tester.ensureVisible(retry);
    await tester.pump();
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();

    expect(repository.getChildrenCalls, 2);
    expect(find.byKey(const ValueKey('child-profile-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('child-profile-7')), findsOneWidget);
  });

  testWidgets('화면 dispose 뒤 늦은 목록 응답은 화면 상태를 변경하지 않는다', (tester) async {
    final pending = Completer<List<ChildSummaryDto>>();
    final controller = GuardianChildController(
      _FakeChildRepository(pending: pending),
    );
    addTearDown(controller.dispose);
    final load = controller.loadChildren();
    await _pumpScreen(tester, controller: controller);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    pending.complete([_child(id: 3)]);
    await load;
    await tester.pump();

    expect(find.byType(ProfileSelectionScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('초기 자동 선택은 체크하지 않고 명시적으로 선택한 아이만 표시한다', (tester) async {
    final children = [_child(id: 3), _child(id: 7)];
    final controller = await _loadedController(children);
    addTearDown(controller.dispose);
    await _pumpScreen(tester, controller: controller);

    expect(controller.selectedChildId, 3);
    expect(controller.hasExplicitChildSelection, isFalse);
    expect(
      find.byKey(const ValueKey('child-profile-selected-3')),
      findsNothing,
    );

    controller.selectChild(children[1]);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('child-profile-selected-7')),
      findsOneWidget,
    );
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('child-profile-7')),
    );
    expect(semantics.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(semantics.label, contains('선택됨'));
  });

  testWidgets('stale 선택 childId가 사라지면 새 첫 아이를 선택 표시하지 않는다', (tester) async {
    final repository = _FakeChildRepository(
      children: [_child(id: 3), _child(id: 7)],
    );
    final controller = GuardianChildController(repository);
    addTearDown(controller.dispose);
    await controller.loadChildren();
    controller.selectChild(controller.children.last);
    repository.children = [_child(id: 11)];
    await controller.loadChildren();
    await _pumpScreen(tester, controller: controller);

    expect(controller.selectedChildId, 11);
    expect(controller.hasExplicitChildSelection, isFalse);
    expect(
      find.byKey(const ValueKey('child-profile-selected-11')),
      findsNothing,
    );
  });

  testWidgets('태블릿 가로는 2열이고 세로·휴대폰·확대 글꼴은 overflow가 없다', (tester) async {
    final controller = await _loadedController([
      _child(id: 3, nickname: '하늘', age: 6),
      _child(id: 7, nickname: '바다', age: 8),
    ]);
    addTearDown(controller.dispose);

    await _pumpScreen(
      tester,
      controller: controller,
      size: const Size(1280, 800),
    );
    final guardianWide = tester.getTopLeft(
      find.byKey(const ValueKey('guardian-role-card')),
    );
    final childWide = tester.getTopLeft(
      find.byKey(const ValueKey('child-role-card')),
    );
    expect(guardianWide.dy, childWide.dy);
    expect(guardianWide.dx, lessThan(childWide.dx));
    expect(tester.takeException(), isNull);

    for (final variant in [
      (const Size(800, 1280), 1.0),
      (const Size(412, 915), 1.0),
      (const Size(320, 640), 1.0),
      (const Size(412, 915), 2.0),
    ]) {
      await _pumpScreen(
        tester,
        controller: controller,
        size: variant.$1,
        textScale: variant.$2,
      );
      final guardianTop = tester.getTopLeft(
        find.byKey(const ValueKey('guardian-role-card')),
      );
      final childTop = tester.getTopLeft(
        find.byKey(const ValueKey('child-role-card')),
      );
      expect(childTop.dy, greaterThan(guardianTop.dy), reason: '${variant.$1}');
      expect(tester.takeException(), isNull, reason: '${variant.$1}');
    }
  });

  testWidgets('상호작용 semantics는 보호자·아이·추가·설정 순서를 갖는다', (tester) async {
    final controller = await _loadedController([_child(id: 3)]);
    addTearDown(controller.dispose);
    await _pumpScreen(tester, controller: controller);

    final guardian = tester.getSemantics(
      find.byKey(const ValueKey('guardian-profile')),
    );
    final child = tester.getSemantics(
      find.byKey(const ValueKey('child-profile-3')),
    );
    final add = tester.getSemantics(
      find.byKey(const ValueKey('add-child-profile')),
    );
    final settings = tester.getSemantics(
      find.byKey(const ValueKey('profile-selection-settings')),
    );

    expect(guardian.flagsCollection.isButton, isTrue);
    expect(child.flagsCollection.isButton, isTrue);
    expect(add.flagsCollection.isButton, isTrue);
    expect(settings.flagsCollection.isButton, isTrue);
    expect((guardian.sortKey! as OrdinalSortKey).order, 1);
    expect((child.sortKey! as OrdinalSortKey).order, 2);
    expect((add.sortKey! as OrdinalSortKey).order, 3);
    expect((settings.sortKey! as OrdinalSortKey).order, 4);
  });

  testWidgets('아동 카드는 기존 profileImageUrl·preferredCharacter 계약을 유지한다', (
    tester,
  ) async {
    final controller = await _loadedController([
      _child(id: 3, preferredCharacter: 'PRINCESS'),
    ]);
    addTearDown(controller.dispose);
    await _pumpScreen(tester, controller: controller);

    final avatar = tester.widget<CircleAvatar>(
      find.descendant(
        of: find.byKey(const ValueKey('child-profile-3')),
        matching: find.byType(CircleAvatar),
      ),
    );
    expect(avatar.backgroundImage, isA<AssetImage>());
    expect(
      (avatar.backgroundImage! as AssetImage).assetName,
      'assets/characters/costumes/dodam_princess.png',
    );
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required GuardianChildController controller,
  Size size = const Size(1280, 800),
  double textScale = 1,
  ValueChanged<BuildContext>? onGuardianSelected,
  ChildProfileSelected? onChildSelected,
  ValueChanged<BuildContext>? onAddChild,
  ChildProfileSelected? onEditChild,
  ValueChanged<BuildContext>? onSettings,
  Widget? headerAction,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ProfileSelectionScreen(
        controller: controller,
        onGuardianSelected: onGuardianSelected ?? (_) {},
        onChildSelected: onChildSelected ?? (_, _) {},
        onAddChild: onAddChild,
        onEditChild: onEditChild,
        onSettings: onSettings,
        headerAction: headerAction,
      ),
    ),
  );
  await tester.pump();
}

Future<GuardianChildController> _loadedController(
  List<ChildSummaryDto> children,
) async {
  final controller = GuardianChildController(
    _FakeChildRepository(children: children),
  );
  await controller.loadChildren();
  return controller;
}

ChildSummaryDto _child({
  required int id,
  String nickname = '도담이',
  int age = 7,
  String? profileImageUrl,
  String? preferredCharacter = 'BASE',
}) => ChildSummaryDto(
  childId: id,
  nickname: nickname,
  birthDate: age <= 0 ? '' : '2019-03-14',
  age: age,
  profileImageUrl: profileImageUrl,
  preferredCharacter: preferredCharacter,
  questionDifficulty: 'PRESCHOOL',
  tutorialStatus: 'NOT_STARTED',
  relationshipType: 'MOTHER',
  recentActivity: const ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

final class _FakeChildRepository implements ChildRepository {
  _FakeChildRepository({this.children = const [], this.error, this.pending});

  List<ChildSummaryDto> children;
  Object? error;
  Completer<List<ChildSummaryDto>>? pending;
  int getChildrenCalls = 0;

  @override
  Future<List<ChildSummaryDto>> getChildren() async {
    getChildrenCalls += 1;
    if (pending case final pending?) return pending.future;
    if (error case final error?) throw error;
    return List.of(children);
  }

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
