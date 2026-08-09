import 'package:dodam/features/settings/application/notification_settings_controller.dart';
import 'package:dodam/features/settings/data/dto/notification_settings_dtos.dart';
import 'package:dodam/features/settings/domain/repositories/notification_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationSettingsController', () {
    test('조회에 성공하면 값을 채우고 dirty가 아니며 저장이 닫혀 있다', () async {
      final controller = NotificationSettingsController(
        _FakeRepository(settings: _defaults),
      );

      await controller.load();

      expect(controller.status, NotificationSettingsStatus.ready);
      expect(controller.settings?.analysisCompleted, isTrue);
      expect(controller.settings?.marketing, isFalse);
      expect(controller.isDirty, isFalse);
      expect(controller.canSave, isFalse);
    });

    test('조회에 실패하면 error 상태가 된다', () async {
      final controller = NotificationSettingsController(
        _FakeRepository(loadError: Exception('boom')),
      );

      await controller.load();

      expect(controller.status, NotificationSettingsStatus.error);
      expect(controller.error, isNotNull);
    });

    test('토글을 바꾸면 dirty가 되고 저장이 열린다', () async {
      final controller = NotificationSettingsController(_FakeRepository());
      await controller.load();

      controller.setMarketing(true);

      expect(controller.settings?.marketing, isTrue);
      expect(controller.isDirty, isTrue);
      expect(controller.canSave, isTrue);
    });

    test('원래 값으로 되돌리면 dirty가 풀려 저장이 닫힌다', () async {
      final controller = NotificationSettingsController(_FakeRepository());
      await controller.load();

      controller.setCommunity(false);
      controller.setCommunity(true);

      expect(controller.isDirty, isFalse);
      expect(controller.canSave, isFalse);
    });

    test('저장은 네 필드를 한 번에 보낸다 — 토글마다 보내지 않는다', () async {
      final repository = _FakeRepository();
      final controller = NotificationSettingsController(repository);
      await controller.load();

      controller.setAnalysisCompleted(false);
      controller.setCommunity(false);
      controller.setServiceNotice(false);
      controller.setMarketing(true);
      expect(repository.updateCount, 0);

      final succeeded = await controller.save();

      expect(succeeded, isTrue);
      expect(repository.updateCount, 1);
      final sent = repository.lastSent!;
      expect(sent.analysisCompleted, isFalse);
      expect(sent.community, isFalse);
      expect(sent.serviceNotice, isFalse);
      expect(sent.marketing, isTrue);
      // 저장 성공 후에는 서버 응답이 곧 저장값이므로 dirty가 풀린다.
      expect(controller.isDirty, isFalse);
      expect(controller.canSave, isFalse);
    });

    test('저장에 실패하면 편집값을 지키고 실패 문구를 준다', () async {
      final controller = NotificationSettingsController(
        _FakeRepository(saveError: Exception('boom')),
      );
      await controller.load();
      controller.setMarketing(true);

      final succeeded = await controller.save();

      expect(succeeded, isFalse);
      // 되돌리지 않는다. 사용자가 다시 저장을 눌러 재시도할 수 있어야 한다.
      expect(controller.settings?.marketing, isTrue);
      expect(controller.saveFailureMessage, isNotNull);
      expect(controller.canSave, isTrue);
    });

    test('바뀐 값이 없으면 저장 요청을 보내지 않는다', () async {
      final repository = _FakeRepository();
      final controller = NotificationSettingsController(repository);
      await controller.load();

      final succeeded = await controller.save();

      expect(succeeded, isFalse);
      expect(repository.updateCount, 0);
    });

    test('저장 응답이 요청과 다르면 응답 값을 따른다', () async {
      // 서버가 최종 상태의 주인이다(계약 §0-3 — 응답은 저장 후 최신 값).
      final controller = NotificationSettingsController(
        _FakeRepository(
          savedOverride: const NotificationSettingsDto(
            analysisCompleted: true,
            community: true,
            serviceNotice: true,
            marketing: false,
          ),
        ),
      );
      await controller.load();
      controller.setMarketing(true);

      await controller.save();

      expect(controller.settings?.marketing, isFalse);
      expect(controller.isDirty, isFalse);
    });
  });
}

const _defaults = NotificationSettingsDto(
  analysisCompleted: true,
  community: true,
  serviceNotice: true,
  marketing: false,
);

final class _FakeRepository implements NotificationSettingsRepository {
  _FakeRepository({
    this.settings = _defaults,
    this.loadError,
    this.saveError,
    this.savedOverride,
  });

  final NotificationSettingsDto settings;
  final Object? loadError;
  final Object? saveError;
  final NotificationSettingsDto? savedOverride;

  int updateCount = 0;
  NotificationSettingsDto? lastSent;

  @override
  Future<NotificationSettingsDto> getNotificationSettings() async {
    if (loadError != null) throw loadError!;
    return settings;
  }

  @override
  Future<NotificationSettingsDto> updateNotificationSettings(
    NotificationSettingsDto settings,
  ) async {
    updateCount += 1;
    lastSent = settings;
    if (saveError != null) throw saveError!;
    return savedOverride ?? settings;
  }
}
