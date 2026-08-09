import 'package:dodam/app/router/app_navigation.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/app/router/current_route_observer.dart';
import 'package:dodam/app/router/navigation_tap_guard.dart';
import 'package:dodam/app/router/notification_route_resolver.dart';
import 'package:dodam/features/notification/domain/entities/push_message.dart';
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

  // 아래 둘은 S15P11B209-501 회귀 방지다. 푸시 클릭은 위젯 밖에서 시작돼
  // `context`가 없는데, 그렇다고 `Navigator`를 직접 부르면 화면에서 시작한
  // 이동과 판정이 갈라진다(같은 상황에서 카드 탭은 이동하지 않는데 푸시만
  // 한 장 더 쌓임).
  group('pushNamedOn — 푸시처럼 context 없이 시작하는 이동', () {
    testWidgets('이미 알림함을 보고 있으면 알림함을 한 장 더 쌓지 않는다', (tester) async {
      // 연속 탭 판정과 섞이지 않게 시계를 직접 쥔다.
      var now = DateTime(2026, 8, 2, 9);
      final guard = NavigationTapGuard(clock: () => now);
      final navigatorKey = GlobalKey<NavigatorState>();
      final routeObserver = CurrentRouteObserver();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [observer, routeObserver],
          initialRoute: '/',
          onGenerateRoute: (settings) => route(settings),
        ),
      );

      // 연결 자원이 없는 푸시의 목적지는 알림함 목록이다(푸시 계약 §4.3).
      const noResource = PushMessage(
        notificationId: 900,
        type: 'RETENTION_NOTICE',
        title: '보관 기간 안내',
        content: '내용을 확인해 주세요',
      );
      final target = resolvePushRoute(noResource);
      expect(target, AppRoutes.notifications);

      void openPush() => AppNavigation.pushNamedOn(
        navigatorKey.currentState!,
        target,
        currentRouteName: routeObserver.currentRouteName,
        guard: guard,
      );

      openPush();
      await tester.pumpAndSettle();
      expect(observer.countOf(AppRoutes.notifications), 1);
      expect(routeObserver.currentRouteName, AppRoutes.notifications);

      // 연속 탭 창을 한참 벗어난 뒤에도, 이미 그 화면이면 이동하지 않는다.
      now = now.add(const Duration(seconds: 5));
      openPush();
      await tester.pumpAndSettle();

      expect(observer.countOf(AppRoutes.notifications), 1);
    });

    testWidgets('화면에서 시작한 이동과 같은 판정기를 공유한다', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final target = AppRoutes.report('55');

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [observer],
          initialRoute: '/',
          onGenerateRoute: (settings) => route(
            settings,
            onPressed: () {},
          ),
        ),
      );

      // 알림함 카드로 리포트 상세를 여는 도중, 같은 알림의 푸시가 도착한 상황.
      final context = tester.element(find.text('/ 화면'));
      AppNavigation.pushNamed(context, target);
      AppNavigation.pushNamedOn(navigatorKey.currentState!, target);
      await tester.pumpAndSettle();

      expect(observer.countOf(target), 1);
    });
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
