import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/child/data/repositories/mock_child_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('보호자와 등록된 아동 프로필을 함께 표시한다', (tester) async {
    final controller = GuardianChildController(const MockChildRepository());
    await controller.loadChildren();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSelectionScreen(
          controller: controller,
          onGuardianSelected: (_) {},
          onChildSelected: (_, _) {},
        ),
      ),
    );

    expect(find.text('누가 도담을 이용하나요?'), findsOneWidget);
    expect(find.text('보호자 프로필'), findsOneWidget);
    expect(find.text('아동 프로필'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('child-profile-3')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('child-profile-carousel')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('add-child-profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-child-profiles')), findsOneWidget);
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('child-profile-3'))).dy,
      lessThanOrEqualTo(600),
    );
  });

  testWidgets('아동 카드는 아이의 캐릭터 이미지를 프로필로 보여준다', (tester) async {
    final controller = GuardianChildController(const MockChildRepository());
    await controller.loadChildren();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSelectionScreen(
          controller: controller,
          onGuardianSelected: (_) {},
          onChildSelected: (_, _) {},
        ),
      ),
    );

    final avatar = tester.widget<CircleAvatar>(
      find.descendant(
        of: find.byKey(const ValueKey('child-profile-3')),
        matching: find.byType(CircleAvatar),
      ),
    );
    // preferredCharacter에 해당하는 캐릭터(코스튬) 에셋을 프로필로 쓴다.
    expect(avatar.backgroundImage, isA<AssetImage>());
    expect(
      (avatar.backgroundImage! as AssetImage).assetName,
      contains('assets/characters/costumes/'),
    );
    // 옛 generic face 아이콘은 더 이상 아동 카드에 쓰지 않는다.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('child-profile-3')),
        matching: find.byIcon(Icons.face_rounded),
      ),
      findsNothing,
    );
  });

  testWidgets('아동 프로필을 누르면 해당 아동을 전달한다', (tester) async {
    final controller = GuardianChildController(const MockChildRepository());
    await controller.loadChildren();
    addTearDown(controller.dispose);
    int? selectedChildId;

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSelectionScreen(
          controller: controller,
          onGuardianSelected: (_) {},
          onChildSelected: (_, child) => selectedChildId = child.childId,
        ),
      ),
    );

    final childProfile = find.byKey(const ValueKey('child-profile-3'));
    await tester.ensureVisible(childProfile);
    await tester.tap(childProfile);

    expect(selectedChildId, 3);
  });

  testWidgets('프로필 편집을 누른 뒤 아동을 선택하면 편집 대상을 전달한다', (tester) async {
    final controller = GuardianChildController(const MockChildRepository());
    await controller.loadChildren();
    addTearDown(controller.dispose);
    int? selectedChildId;
    int? editingChildId;

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSelectionScreen(
          controller: controller,
          onGuardianSelected: (_) {},
          onChildSelected: (_, child) => selectedChildId = child.childId,
          onEditChild: (_, child) => editingChildId = child.childId,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('edit-child-profiles')));
    await tester.pump();
    expect(find.text('수정하거나 삭제할 아이를 선택해 주세요.'), findsOneWidget);

    final childProfile = find.byKey(const ValueKey('child-profile-3'));
    await tester.ensureVisible(childProfile);
    await tester.tap(childProfile);

    expect(editingChildId, 3);
    expect(selectedChildId, isNull);
  });
}
