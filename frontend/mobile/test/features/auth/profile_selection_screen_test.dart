import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('아동 프로필 중심 레이아웃과 작은 보호자 진입 버튼을 렌더링한다', (tester) async {
    final controller = await _loadedController([
      _child(id: 3, nickname: '하늘', age: 6),
      _child(id: 7, nickname: '바다', age: 8),
    ]);
    addTearDown(controller.dispose);

    await _pumpScreen(tester, controller: controller);

    expect(find.text('누가 도담이와 함께할까요?'), findsOneWidget);
    expect(find.text('활동을 시작할 아동 프로필을 선택해 주세요.'), findsOneWidget);
    expect(find.text('보호자 모드로'), findsOneWidget);
    expect(find.byKey(const ValueKey('child-profile-section')), findsOneWidget);
    expect(find.byKey(const ValueKey('child-profile-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-role-card')), findsNothing);
    expect(find.byKey(const ValueKey('child-role-card')), findsNothing);
    expect(find.text('보호자로 시작하기'), findsNothing);
    expect(find.text('아이 모드'), findsNothing);
    expect(find.text('아이로 시작하기'), findsNothing);
    expect(find.byKey(const ValueKey('child-dodami-image')), findsNothing);

    final guardian = tester.widget<Image>(
      find.byKey(const ValueKey('guardian-dodami-image')),
    );
    expect(
      (guardian.image as AssetImage).assetName,
      'assets/images/role_selection/guardian_dodami.png',
    );
    expect(guardian.fit, BoxFit.contain);

    final context = tester.element(find.byType(ProfileSelectionScreen));
    const asset = 'assets/images/role_selection/guardian_dodami.png';
    final bytes = await DefaultAssetBundle.of(context).load(asset);
    expect(bytes.lengthInBytes, greaterThan(0), reason: asset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('보호자 모드 버튼을 연속 탭해도 callback은 한 번이다', (tester) async {
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
          .getSize(find.byKey(const ValueKey('guardian-mode-action')))
          .shortestSide,
      greaterThanOrEqualTo(48),
    );
    expect(tester.getSemantics(guardian).label, '보호자 모드로 이동');
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

    expect(find.text('하늘'), findsOneWidget);
    expect(find.text('6세'), findsOneWidget);
    expect(find.text('바다'), findsOneWidget);
    expect(find.text('8세'), findsOneWidget);
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
    expect(label.maxLines, 2);
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

    expect(find.byKey(const ValueKey('child-profile-grid')), findsOneWidget);
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

  testWidgets('아이 다수는 반응형 그리드와 화면 스크롤로 마지막 항목에 접근한다', (tester) async {
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

    final grid = find.byKey(const ValueKey('child-profile-grid'));
    expect(grid, findsOneWidget);
    final outerScroll = find.byKey(const ValueKey('profile-selection-scroll'));
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('child-profile-8')),
      outerScroll,
      const Offset(0, -300),
    );
    expect(find.byKey(const ValueKey('child-profile-8')), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('add-child-profile')),
      outerScroll,
      const Offset(0, -300),
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
    // 편집 모드의 카드 탭은 삭제 대상 고르기라, 개별 편집은 카드의 연필로 간다.
    await tester.tap(find.byKey(const ValueKey('child-profile-edit-3')));
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

  testWidgets('요구 viewport와 글자 배율에서 반응형 배치와 overflow를 검증한다', (tester) async {
    final controller = await _loadedController([
      _child(id: 3, nickname: '하늘', age: 6),
      _child(id: 7, nickname: '바다', age: 8),
    ]);
    addTearDown(controller.dispose);

    for (final variant in [
      (const Size(1280, 800), 1.0),
      (const Size(844, 390), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(1280, 800), 2.0),
      (const Size(844, 390), 2.0),
      (const Size(390, 844), 2.0),
    ]) {
      await _pumpScreen(
        tester,
        controller: controller,
        size: variant.$1,
        textScale: variant.$2,
      );
      final title = find.byKey(const ValueKey('profile-selection-title'));
      final guardian = find.byKey(const ValueKey('guardian-mode-action'));
      expect(title, findsOneWidget);
      expect(guardian, findsOneWidget);
      expect(find.byKey(const ValueKey('child-profile-grid')), findsOneWidget);
      expect(
        tester.getSize(guardian).height,
        greaterThanOrEqualTo(48),
        reason: '${variant.$1} scale ${variant.$2}',
      );
      if (variant.$1.width >= 720) {
        expect(
          tester.getTopLeft(title).dx,
          lessThan(tester.getTopLeft(guardian).dx),
          reason: '${variant.$1} scale ${variant.$2}',
        );
      } else {
        expect(
          tester.getTopLeft(guardian).dy,
          greaterThan(tester.getTopLeft(title).dy),
          reason: '${variant.$1} scale ${variant.$2}',
        );
      }
      expect(
        tester.takeException(),
        isNull,
        reason: '${variant.$1} scale ${variant.$2}',
      );
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
    expect(guardian.label, '보호자 모드로 이동');
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

    final avatar = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('child-profile-3')),
        matching: find.byType(Image),
      ),
    );
    expect(avatar.image, isA<AssetImage>());
    expect(
      (avatar.image as AssetImage).assetName,
      'assets/characters/costumes/dodam_princess.png',
    );
  });

  testWidgets('인증 상대 경로 사진이 성공하면 캐릭터보다 우선 표시한다', (tester) async {
    final controller = await _loadedController([
      _child(
        id: 3,
        profileImageUrl: '/api/v1/child-profile-images/file-3/file',
        preferredCharacter: 'DINO',
      ),
    ]);
    addTearDown(controller.dispose);
    final requested = <String>[];

    await _pumpScreen(
      tester,
      controller: controller,
      imageFetcher: (url) async {
        requested.add(url);
        return base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
      },
    );
    await tester.pumpAndSettle();

    expect(requested, ['/api/v1/child-profile-images/file-3/file']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('child-profile-3')),
        matching: find.byKey(const ValueKey('authenticated-image-success')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('인증 사진 404는 preferredCharacter로 fallback한다', (tester) async {
    final controller = await _loadedController([
      _child(
        id: 3,
        profileImageUrl: '/api/v1/child-profile-images/missing/file',
        preferredCharacter: 'PRINCESS',
      ),
    ]);
    addTearDown(controller.dispose);

    await _pumpScreen(
      tester,
      controller: controller,
      imageFetcher: (_) async => throw StateError('404'),
    );
    await tester.pumpAndSettle();

    final fallback = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('child-profile-3')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (fallback.image as AssetImage).assetName,
      'assets/characters/costumes/dodam_princess.png',
    );
  });

  testWidgets('인증 사진 decode 실패와 캐릭터 null은 BASE로 fallback한다', (tester) async {
    final controller = await _loadedController([
      _child(
        id: 3,
        profileImageUrl: '/api/v1/child-profile-images/broken/file',
        preferredCharacter: null,
      ),
    ]);
    addTearDown(controller.dispose);

    await _pumpScreen(
      tester,
      controller: controller,
      imageFetcher: (_) async => Uint8List.fromList(const [1, 2, 3]),
    );
    await tester.pumpAndSettle();

    final images = tester.widgetList<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('child-profile-3')),
        matching: find.byType(Image),
      ),
    );
    expect(
      images.any(
        (image) =>
            image.image is AssetImage &&
            (image.image as AssetImage).assetName ==
                'assets/characters/costumes/dodam_base.png',
      ),
      isTrue,
    );
  });

  group('다중 선택 삭제', () {
    testWidgets('길게 누르면 편집 모드로 들어가며 그 아이가 선택된다', (tester) async {
      final controller = await _loadedController([
        _child(id: 3),
        _child(id: 7),
      ]);
      addTearDown(controller.dispose);
      var startedChildId = 0;
      await _pumpScreen(
        tester,
        controller: controller,
        onEditChild: (_, _) {},
        onChildSelected: (_, child) => startedChildId = child.childId,
      );

      await tester.longPress(find.byKey(const ValueKey('child-profile-3')));
      await tester.pumpAndSettle();

      expect(find.text('수정하거나 삭제할 아이를 선택해 주세요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('child-profile-delete-selected-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('child-profile-delete-selected-7')),
        findsNothing,
      );
      expect(find.text('선택한 1명 삭제'), findsOneWidget);
      // 길게 누르기가 활동 시작을 겸하면 안 된다.
      expect(startedChildId, 0);
    });

    testWidgets('편집 모드 탭은 선택을 토글하고 삭제 버튼 활성 상태를 바꾼다', (tester) async {
      final controller = await _loadedController([
        _child(id: 3),
        _child(id: 7),
      ]);
      addTearDown(controller.dispose);
      await _pumpScreen(tester, controller: controller, onEditChild: (_, _) {});

      await tester.longPress(find.byKey(const ValueKey('child-profile-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('child-profile-7')));
      await tester.pump();

      expect(find.text('선택한 2명 삭제'), findsOneWidget);
      expect(_deleteButton(tester).onPressed, isNotNull);

      // 같은 카드를 다시 누르면 선택이 풀린다.
      await tester.tap(find.byKey(const ValueKey('child-profile-3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('child-profile-7')));
      await tester.pump();

      expect(find.text('삭제할 아이를 선택해 주세요'), findsOneWidget);
      expect(_deleteButton(tester).onPressed, isNull);
    });

    testWidgets('삭제를 확인하면 고른 수만큼 지우고 목록을 갱신한다', (tester) async {
      final repository = _FakeChildRepository(
        children: [_child(id: 3), _child(id: 7), _child(id: 11)],
      );
      final controller = GuardianChildController(repository);
      addTearDown(controller.dispose);
      await controller.loadChildren();
      await _pumpScreen(tester, controller: controller, onEditChild: (_, _) {});

      await tester.longPress(find.byKey(const ValueKey('child-profile-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('child-profile-7')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete-selected-profiles')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('delete-profiles-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('선택한 2명의 프로필을 삭제할까요?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete-profiles-confirm')));
      await tester.pumpAndSettle();

      expect(repository.deletedChildIds, [3, 7]);
      expect(controller.children.map((child) => child.childId), [11]);
      expect(find.byKey(const ValueKey('child-profile-3')), findsNothing);
      expect(find.byKey(const ValueKey('child-profile-7')), findsNothing);
      expect(find.byKey(const ValueKey('child-profile-11')), findsOneWidget);
    });

    testWidgets('한 명만 고르면 기존 연쇄 삭제 경고 문구를 그대로 쓴다', (tester) async {
      final controller = await _loadedController([
        _child(id: 3, nickname: '민재'),
      ]);
      addTearDown(controller.dispose);
      await _pumpScreen(tester, controller: controller, onEditChild: (_, _) {});

      await tester.longPress(find.byKey(const ValueKey('child-profile-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-selected-profiles')));
      await tester.pumpAndSettle();

      expect(find.text('아이 프로필을 삭제할까요?'), findsOneWidget);
      expect(
        find.text('민재의 그림과 대화, 활동 기록도 함께 삭제되며 되돌릴 수 없어요.'),
        findsOneWidget,
      );
    });

    testWidgets('확인을 취소하면 아무것도 지우지 않고 선택을 유지한다', (tester) async {
      final repository = _FakeChildRepository(
        children: [_child(id: 3), _child(id: 7)],
      );
      final controller = GuardianChildController(repository);
      addTearDown(controller.dispose);
      await controller.loadChildren();
      await _pumpScreen(tester, controller: controller, onEditChild: (_, _) {});

      await tester.longPress(find.byKey(const ValueKey('child-profile-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-selected-profiles')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(repository.deletedChildIds, isEmpty);
      expect(find.byKey(const ValueKey('child-profile-3')), findsOneWidget);
      expect(find.text('선택한 1명 삭제'), findsOneWidget);
    });

    testWidgets('일부만 실패하면 성공분만 사라지고 실패 수를 알린다', (tester) async {
      final repository = _FakeChildRepository(
        children: [_child(id: 3), _child(id: 7)],
      )..deleteFailures = {7};
      final controller = GuardianChildController(repository);
      addTearDown(controller.dispose);
      await controller.loadChildren();
      await _pumpScreen(tester, controller: controller, onEditChild: (_, _) {});

      await tester.longPress(find.byKey(const ValueKey('child-profile-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('child-profile-7')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete-selected-profiles')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-profiles-confirm')));
      await tester.pumpAndSettle();

      expect(repository.deletedChildIds, [3, 7]);
      expect(find.byKey(const ValueKey('child-profile-3')), findsNothing);
      expect(find.byKey(const ValueKey('child-profile-7')), findsOneWidget);
      expect(find.text('1명의 프로필을 삭제하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      // 실패한 아이는 골라진 채로 남아 바로 재시도할 수 있다.
      expect(find.text('선택한 1명 삭제'), findsOneWidget);
    });

    testWidgets('편집을 끝내면 모드와 선택이 함께 풀린다', (tester) async {
      final controller = await _loadedController([_child(id: 3)]);
      addTearDown(controller.dispose);
      var startedChildId = 0;
      await _pumpScreen(
        tester,
        controller: controller,
        onEditChild: (_, _) {},
        onChildSelected: (_, child) => startedChildId = child.childId,
      );

      await tester.longPress(find.byKey(const ValueKey('child-profile-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('finish-profile-editing')));
      await tester.pumpAndSettle();

      expect(find.text('수정하거나 삭제할 아이를 선택해 주세요.'), findsNothing);
      expect(
        find.byKey(const ValueKey('child-profile-delete-selected-3')),
        findsNothing,
      );
      // 편집이 끝났으니 탭은 다시 활동 시작이다.
      await tester.tap(find.byKey(const ValueKey('child-profile-3')));
      expect(startedChildId, 3);
    });

    testWidgets('편집 배선이 없으면 길게 눌러도 편집 모드로 가지 않는다', (tester) async {
      final controller = await _loadedController([_child(id: 3)]);
      addTearDown(controller.dispose);
      await _pumpScreen(tester, controller: controller);

      await tester.longPress(find.byKey(const ValueKey('child-profile-3')));
      await tester.pumpAndSettle();

      expect(find.text('수정하거나 삭제할 아이를 선택해 주세요.'), findsNothing);
      expect(
        find.byKey(const ValueKey('delete-selected-profiles')),
        findsNothing,
      );
    });

    testWidgets('좁은 폭과 큰 글자에서도 편집 액션 줄이 overflow하지 않는다', (tester) async {
      final controller = await _loadedController([
        _child(id: 3),
        _child(id: 7),
      ]);
      addTearDown(controller.dispose);
      await _pumpScreen(
        tester,
        controller: controller,
        onEditChild: (_, _) {},
        size: const Size(390, 844),
        textScale: 2,
      );

      await tester.longPress(find.byKey(const ValueKey('child-profile-3')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('delete-selected-profiles')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('finish-profile-editing')),
        findsOneWidget,
      );
    });
  });
}

FilledButton _deleteButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey('delete-selected-profiles')),
);

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
  ImageByteFetcher? imageFetcher,
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
        imageFetcher: imageFetcher,
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

  /// 삭제가 요청된 순서. 호출 횟수와 대상을 함께 본다.
  final List<int> deletedChildIds = [];

  /// 서버 삭제가 실패하는 아이들. 부분 실패를 재현한다.
  Set<int> deleteFailures = <int>{};

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
  Future<void> deleteChild(int childId) async {
    deletedChildIds.add(childId);
    if (deleteFailures.contains(childId)) {
      throw StateError('아이 프로필 삭제 실패');
    }
    children = children
        .where((child) => child.childId != childId)
        .toList(growable: false);
  }

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
