import 'package:dodam/app/router/navigation_tap_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 시간을 손으로 돌리는 가짜 시계. 실제 지연을 기다리지 않고 창(window)
  /// 안팎을 검증하기 위해 쓴다.
  late DateTime now;
  DateTime clock() => now;

  setUp(() => now = DateTime(2026, 7, 28, 9));

  test('처음 요청한 화면은 열어 준다', () {
    final guard = NavigationTapGuard(clock: clock);

    expect(guard.shouldAllow('/guardian/activities'), isTrue);
  });

  test('창 안에서 같은 화면을 다시 요청하면 막는다', () {
    final guard = NavigationTapGuard(
      window: const Duration(milliseconds: 600),
      clock: clock,
    );

    expect(guard.shouldAllow('/guardian/activities'), isTrue);
    now = now.add(const Duration(milliseconds: 100));
    expect(guard.shouldAllow('/guardian/activities'), isFalse);
  });

  test('창을 넘기면 같은 화면도 다시 열 수 있다', () {
    final guard = NavigationTapGuard(
      window: const Duration(milliseconds: 600),
      clock: clock,
    );

    expect(guard.shouldAllow('/guardian/activities'), isTrue);
    now = now.add(const Duration(milliseconds: 700));
    expect(guard.shouldAllow('/guardian/activities'), isTrue);
  });

  test('다른 화면으로 가는 요청은 연달아 눌러도 막지 않는다', () {
    final guard = NavigationTapGuard(clock: clock);

    expect(guard.shouldAllow('/guardian/activities'), isTrue);
    expect(guard.shouldAllow('/guardian/reports/1'), isTrue);
  });

  test('이미 그 화면에 있으면 시간과 무관하게 막는다', () {
    final guard = NavigationTapGuard(clock: clock);
    now = now.add(const Duration(days: 1));

    expect(
      guard.shouldAllow(
        '/guardian/activities',
        currentRouteName: '/guardian/activities',
      ),
      isFalse,
    );
  });

  test('reset 후에는 곧바로 같은 화면을 다시 열 수 있다', () {
    final guard = NavigationTapGuard(clock: clock);

    expect(guard.shouldAllow('/guardian/activities'), isTrue);
    guard.reset();

    expect(guard.shouldAllow('/guardian/activities'), isTrue);
  });
}
