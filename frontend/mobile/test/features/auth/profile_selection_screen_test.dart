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
}
