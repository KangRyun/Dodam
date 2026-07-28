import 'package:dodam/app/widgets/guardian_shell.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 탭을 떠났다 돌아와도 상태가 남는지 보기 위한 화면.
  /// 누른 횟수를 자기 State에 들고 있으므로, 위젯이 버려지면 0으로 돌아간다.
  Widget counterTab(String label) => _CounterScreen(label: label);

  GuardianShellTab tab(
    String label,
    IconData icon,
    WidgetBuilder builder,
  ) => GuardianShellTab(
    item: AppBottomTabItem(icon: icon, selectedIcon: icon, label: label),
    builder: builder,
  );

  Widget subject({RouteFactory? routeFactory}) => MaterialApp(
    theme: ThemeData(platform: TargetPlatform.android),
    home: GuardianShell(
      routeFactory: routeFactory,
      tabs: [
        tab('홈', Icons.home_rounded, (_) => counterTab('홈')),
        tab('기록', Icons.article_rounded, (_) => counterTab('기록')),
        tab('알림', Icons.notifications_rounded, (_) => counterTab('알림')),
        tab('설정', Icons.settings_rounded, (_) => counterTab('설정')),
      ],
    ),
  );

  testWidgets('네 개의 하단 탭을 보여주고 홈 탭에서 시작한다', (tester) async {
    await tester.pumpWidget(subject());

    expect(find.byType(AppBottomTabBar), findsOneWidget);
    for (final label in ['홈', '기록', '알림', '설정']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('홈 화면'), findsOneWidget);
  });

  testWidgets('탭을 옮기면 그 탭의 화면이 보인다', (tester) async {
    await tester.pumpWidget(subject());

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();

    expect(find.text('기록 화면'), findsOneWidget);
  });

  testWidgets('탭을 떠났다 돌아와도 화면 상태가 유지된다', (tester) async {
    await tester.pumpWidget(subject());

    await tester.tap(find.text('세어보기'));
    await tester.tap(find.text('세어보기'));
    await tester.pumpAndSettle();
    expect(find.text('누른 횟수: 2'), findsOneWidget);

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();

    expect(find.text('누른 횟수: 2'), findsOneWidget);
  });

  testWidgets('탭마다 뒤로가기 스택이 따로 남는다', (tester) async {
    await tester.pumpWidget(
      subject(
        routeFactory: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('상세 ${settings.name}')),
        ),
      ),
    );

    // 기록 탭에서 상세로 들어간다.
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('상세로'));
    await tester.pumpAndSettle();
    expect(find.text('상세 /detail'), findsOneWidget);

    // 홈 탭에 다녀와도 기록 탭은 상세 화면 그대로다.
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();

    expect(find.text('상세 /detail'), findsOneWidget);
  });

  testWidgets('뒤로가기는 먼저 현재 탭 안에서 처리한다', (tester) async {
    await tester.pumpWidget(
      subject(
        routeFactory: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('상세 ${settings.name}')),
        ),
      ),
    );

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('상세로'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('상세 /detail'), findsNothing);
    expect(find.text('기록 화면'), findsOneWidget);
  });

  testWidgets('탭 뿌리에서 뒤로가기를 누르면 첫 탭으로 돌아온다', (tester) async {
    await tester.pumpWidget(subject());

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.text('설정 화면'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('홈 화면'), findsOneWidget);
  });

  testWidgets('첫 탭 뿌리에서는 한 번 더 눌러야 닫힌다고 안내한다', (tester) async {
    await tester.pumpWidget(subject());

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('한 번 더 누르면 앱이 닫혀요'), findsOneWidget);
    expect(find.text('홈 화면'), findsOneWidget);
  });

  testWidgets('iOS에서는 첫 탭 뿌리 뒤로가기에 종료 안내를 띄우지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: GuardianShell(
          tabs: [
            tab('홈', Icons.home_rounded, (_) => counterTab('홈')),
            tab('설정', Icons.settings_rounded, (_) => counterTab('설정')),
          ],
        ),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('한 번 더 누르면 앱이 닫혀요'), findsNothing);
  });

  testWidgets('보고 있는 탭을 다시 누르면 그 탭의 첫 화면으로 돌아간다', (tester) async {
    await tester.pumpWidget(
      subject(
        routeFactory: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('상세 ${settings.name}')),
        ),
      ),
    );

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('상세로'));
    await tester.pumpAndSettle();
    expect(find.text('상세 /detail'), findsOneWidget);

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();

    expect(find.text('상세 /detail'), findsNothing);
    expect(find.text('기록 화면'), findsOneWidget);
  });
}

class _CounterScreen extends StatefulWidget {
  const _CounterScreen({required this.label});

  final String label;

  @override
  State<_CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<_CounterScreen> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('${widget.label} 화면'),
        Text('누른 횟수: $_count'),
        TextButton(
          onPressed: () => setState(() => _count++),
          child: const Text('세어보기'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pushNamed('/detail'),
          child: const Text('상세로'),
        ),
      ],
    ),
  );
}
