import 'package:dodam/app/router/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _PushCounter observer;

  setUp(() => observer = _PushCounter());

  Route<void> route(RouteSettings settings, {VoidCallback? onPressed}) =>
      MaterialPageRoute<void>(
        settings: settings,
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: onPressed ?? () {},
              child: Text('${settings.name} 화면'),
            ),
          ),
        ),
      );

  testWidgets('연속으로 두 번 눌러도 화면은 한 번만 열린다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        initialRoute: '/',
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => AppNavigation.pushNamed(context, '/detail'),
                child: const Text('상세로'),
              ),
            ),
          ),
        ),
      ),
    );

    final button = find.text('상세로');
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(observer.countOf('/detail'), 1);
  });

  testWidgets('이미 그 화면에 있으면 같은 곳으로 다시 가지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        initialRoute: '/detail',
        onGenerateRoute: (settings) => route(
          settings,
          onPressed: () {},
        ),
      ),
    );

    final context = tester.element(find.text('/detail 화면'));
    AppNavigation.pushNamed(context, '/detail');
    await tester.pumpAndSettle();

    // 최초 진입 1회 외에 추가 push가 없어야 한다.
    expect(observer.countOf('/detail'), 1);
  });

  testWidgets('Navigator가 다르면 서로의 이동을 막지 않는다', (tester) async {
    final left = _PushCounter();
    final right = _PushCounter();

    Widget pane(String label, _PushCounter counter) => Navigator(
      observers: [counter],
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => AppNavigation.pushNamed(context, '/detail'),
            child: Text('$label ${settings.name}'),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(child: pane('왼쪽', left)),
            Expanded(child: pane('오른쪽', right)),
          ],
        ),
      ),
    );

    // 같은 이름의 화면이라도 스택이 다르면 각자 한 번씩 열려야 한다.
    await tester.tap(find.text('왼쪽 /'));
    await tester.pump();
    await tester.tap(find.text('오른쪽 /'));
    await tester.pumpAndSettle();

    expect(left.countOf('/detail'), 1);
    expect(right.countOf('/detail'), 1);
  });

  testWidgets('스택을 비우고 이동하면 곧바로 같은 화면을 다시 열 수 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        initialRoute: '/',
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: settings.name == '/detail'
                    ? () => AppNavigation.resetTo(context, '/detail')
                    : () => AppNavigation.pushNamed(context, '/detail'),
                child: Text('${settings.name} 화면'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('/ 화면'));
    await tester.pumpAndSettle();
    expect(observer.countOf('/detail'), 1);

    await tester.tap(find.text('/detail 화면'));
    await tester.pumpAndSettle();

    expect(observer.countOf('/detail'), 2);
  });
}

class _PushCounter extends NavigatorObserver {
  final Map<String, int> _counts = {};

  int countOf(String routeName) => _counts[routeName] ?? 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) _counts[name] = (_counts[name] ?? 0) + 1;
    super.didPush(route, previousRoute);
  }
}
