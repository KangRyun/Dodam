import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/settings/data/dto/notification_settings_dtos.dart';
import 'package:dodam/features/settings/domain/repositories/notification_settings_repository.dart';
import 'package:dodam/features/settings/presentation/screens/notification_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationSettingsScreen', () {
    testWidgets('조회한 네 값을 스위치로 보여준다', (tester) async {
      await _pumpScreen(tester, _FakeRepository());

      expect(_switchValue(tester, 'notification-settings-analysis'), isTrue);
      expect(
        _switchValue(tester, 'notification-settings-service-notice'),
        isTrue,
      );
      expect(_switchValue(tester, 'notification-settings-community'), isTrue);
      expect(_switchValue(tester, 'notification-settings-marketing'), isFalse);
    });

    testWidgets('바꾸기 전에는 저장 버튼이 비활성, 바꾸면 활성이 된다', (tester) async {
      await _pumpScreen(tester, _FakeRepository());

      VoidCallback? saveOnPressed() => tester
          .widget<AppButton>(
            find.byKey(const ValueKey('notification-settings-save')),
          )
          .onPressed;

      expect(saveOnPressed(), isNull);

      await _toggle(tester, 'notification-settings-marketing');

      expect(saveOnPressed(), isNotNull);
    });

    testWidgets('저장을 누르면 네 값을 한 번에 보낸다', (tester) async {
      final repository = _FakeRepository();
      await _pumpScreen(tester, repository);

      await _toggle(tester, 'notification-settings-analysis');
      await _toggle(tester, 'notification-settings-marketing');
      expect(repository.updateCount, 0);

      await tester.tap(
        find.byKey(const ValueKey('notification-settings-save')),
      );
      await tester.pumpAndSettle();

      expect(repository.updateCount, 1);
      expect(repository.lastSent?.analysisCompleted, isFalse);
      expect(repository.lastSent?.marketing, isTrue);
      expect(find.text('알림 설정을 저장했어요.'), findsOneWidget);
    });

    testWidgets('저장에 실패하면 오류 안내를 띄우고 값을 지킨다', (tester) async {
      await _pumpScreen(tester, _FakeRepository(saveError: Exception('boom')));

      await _toggle(tester, 'notification-settings-community');
      await tester.tap(
        find.byKey(const ValueKey('notification-settings-save')),
      );
      await tester.pumpAndSettle();

      expect(_switchValue(tester, 'notification-settings-community'), isFalse);
      expect(find.text('알림 설정을 저장했어요.'), findsNothing);
    });

    testWidgets('조회에 실패하면 실패 화면을 보여준다', (tester) async {
      await _pumpScreen(tester, _FakeRepository(loadError: Exception('boom')));

      expect(find.text('알림 설정을 불러오지 못했어요'), findsOneWidget);
    });

    testWidgets('기기 알림 권한 안내를 함께 보여준다', (tester) async {
      // 여기서 켜 두어도 OS 권한이 꺼져 있으면 알림이 오지 않는다 — 그 오해를 화면이 먼저 막는다.
      await _pumpScreen(tester, _FakeRepository());

      expect(
        find.textContaining('기기 자체의 알림 권한을 꺼 두면'),
        findsOneWidget,
      );
    });
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  NotificationSettingsRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(home: NotificationSettingsScreen(repository: repository)),
  );
  await tester.pumpAndSettle();
}

bool _switchValue(WidgetTester tester, String key) =>
    tester.widget<Switch>(find.byKey(ValueKey(key))).value;

Future<void> _toggle(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

final class _FakeRepository implements NotificationSettingsRepository {
  _FakeRepository({this.loadError, this.saveError});

  final Object? loadError;
  final Object? saveError;

  int updateCount = 0;
  NotificationSettingsDto? lastSent;

  @override
  Future<NotificationSettingsDto> getNotificationSettings() async {
    if (loadError != null) throw loadError!;
    return const NotificationSettingsDto(
      analysisCompleted: true,
      community: true,
      serviceNotice: true,
      marketing: false,
    );
  }

  @override
  Future<NotificationSettingsDto> updateNotificationSettings(
    NotificationSettingsDto settings,
  ) async {
    updateCount += 1;
    lastSent = settings;
    if (saveError != null) throw saveError!;
    return settings;
  }
}
