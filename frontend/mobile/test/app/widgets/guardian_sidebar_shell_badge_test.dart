import 'package:dodam/app/widgets/guardian_sidebar_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject(ValueListenable<int> badgeCount) => MaterialApp(
    home: GuardianSidebarShell(
      onSwitchProfile: (_) {},
      destinations: [
        GuardianNavItem(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
          label: '홈',
          builder: (_) => const SizedBox.shrink(),
        ),
        GuardianNavItem(
          icon: Icons.notifications_none_rounded,
          selectedIcon: Icons.notifications_rounded,
          label: '알림',
          builder: (_) => const SizedBox.shrink(),
          badgeCount: badgeCount,
        ),
      ],
    ),
  );

  testWidgets('미열람이 없으면 배지를 그리지 않는다', (tester) async {
    await tester.pumpWidget(subject(ValueNotifier(0)));

    expect(find.text('0'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('읽지 않은 알림')), findsNothing);
  });

  testWidgets('미열람 수를 배지로 보여준다', (tester) async {
    await tester.pumpWidget(subject(ValueNotifier(3)));

    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('읽지 않은 알림 3건'), findsOneWidget);
  });

  testWidgets('배지를 붙이지 않은 항목에는 배지가 없다', (tester) async {
    await tester.pumpWidget(subject(ValueNotifier(3)));

    // '홈' 항목은 badgeCount가 null이라 배지가 하나뿐이어야 한다.
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('100건 이상은 99+로 줄여 레일 폭을 넘기지 않는다', (tester) async {
    await tester.pumpWidget(subject(ValueNotifier(128)));

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('128'), findsNothing);
    expect(find.bySemanticsLabel('읽지 않은 알림 99개 이상'), findsOneWidget);
  });

  testWidgets('99건은 그대로 보여준다', (tester) async {
    await tester.pumpWidget(subject(ValueNotifier(99)));

    expect(find.text('99'), findsOneWidget);
  });

  testWidgets('수가 바뀌면 배지가 따라 바뀌고 0이 되면 사라진다', (tester) async {
    final badgeCount = ValueNotifier(0);
    addTearDown(badgeCount.dispose);
    await tester.pumpWidget(subject(badgeCount));
    expect(find.text('2'), findsNothing);

    badgeCount.value = 2;
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    badgeCount.value = 0;
    await tester.pump();
    expect(find.text('2'), findsNothing);
  });

  Widget selectionSubject(VoidCallback onNotificationSelected) => MaterialApp(
    home: GuardianSidebarShell(
      onSwitchProfile: (_) {},
      destinations: [
        GuardianNavItem(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
          label: '홈',
          builder: (_) => const SizedBox.shrink(),
        ),
        GuardianNavItem(
          icon: Icons.notifications_none_rounded,
          selectedIcon: Icons.notifications_rounded,
          label: '알림',
          builder: (_) => const SizedBox.shrink(),
          onSelected: onNotificationSelected,
        ),
      ],
    ),
  );

  testWidgets('탭을 나갔다 다시 들어오면 그 목적지에 선택을 알린다', (tester) async {
    // IndexedStack이 방문한 탭을 살려 두어 재진입해도 화면의 initState가 다시
    // 돌지 않는다. 재진입 시 갱신은 이 통지에만 기댈 수 있다.
    var selections = 0;
    await tester.pumpWidget(selectionSubject(() => selections += 1));

    await tester.tap(find.text('알림'));
    await tester.pumpAndSettle();
    expect(selections, 1);

    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('알림'));
    await tester.pumpAndSettle();

    expect(selections, 2);
  });

  testWidgets('보고 있는 탭을 다시 눌러도 선택을 알린다', (tester) async {
    // 갱신을 바라고 같은 아이콘을 다시 누르는 것도 흔한 복구 동작이다.
    var selections = 0;
    await tester.pumpWidget(selectionSubject(() => selections += 1));

    await tester.tap(find.text('알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('알림'));
    await tester.pumpAndSettle();

    expect(selections, 2);
  });

  testWidgets('선택 통지를 붙이지 않은 항목은 눌러도 아무 일이 없다', (tester) async {
    var selections = 0;
    await tester.pumpWidget(selectionSubject(() => selections += 1));

    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();

    expect(selections, 0);
  });

  testWidgets('큰 글자 배율에서도 레일이 넘치지 않는다', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: subject(ValueNotifier(128)),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('99+'), findsOneWidget);
  });
}
