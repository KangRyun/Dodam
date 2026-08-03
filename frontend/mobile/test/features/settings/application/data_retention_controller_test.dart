import 'package:dodam/features/settings/application/data_retention_controller.dart';
import 'package:dodam/features/settings/data/dto/data_retention_dtos.dart';
import 'package:dodam/features/settings/domain/repositories/data_retention_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataRetentionController', () {
    test('조회에 성공하면 값을 채우고 dirty가 아니며 저장이 닫혀 있다', () async {
      final controller = DataRetentionController(
        _FakeDataRetentionRepository(
          policy: const DataRetentionPolicyDto(
            retentionDays: 180,
            noticeDaysBefore: 30,
            policyStatus: 'PROVISIONAL',
          ),
        ),
      );

      await controller.load();

      expect(controller.status, DataRetentionStatus.ready);
      expect(controller.retentionDays, 180);
      expect(controller.noticeDaysBefore, 30);
      expect(controller.isProvisional, isTrue);
      expect(controller.isDirty, isFalse);
      expect(controller.canSave, isFalse);
    });

    test('조회에 실패하면 error 상태가 된다', () async {
      final controller = DataRetentionController(
        _FakeDataRetentionRepository(loadError: Exception('boom')),
      );

      await controller.load();

      expect(controller.status, DataRetentionStatus.error);
      expect(controller.error, isNotNull);
    });

    test('보관 기간을 바꾸면 dirty가 되고 저장이 열린다', () async {
      final controller = DataRetentionController(_FakeDataRetentionRepository());
      await controller.load();

      controller.setRetentionDays(90);

      expect(controller.retentionDays, 90);
      expect(controller.isDirty, isTrue);
      expect(controller.isNoticeValid, isTrue);
      expect(controller.canSave, isTrue);
    });

    test('보관 기간을 안내 시점 이하로 줄이면 안내 시점을 유효한 최대값으로 맞춘다', () async {
      final controller = DataRetentionController(
        _FakeDataRetentionRepository(
          policy: const DataRetentionPolicyDto(
            retentionDays: 365,
            noticeDaysBefore: 30,
            policyStatus: 'PROVISIONAL',
          ),
        ),
      );
      await controller.load();

      controller.setRetentionDays(30);

      // 30일 보관에서는 "30일 전"이 만료 후 안내가 되어 무효하므로, 프리셋 중
      // 30보다 작은 가장 큰 값(14)으로 다시 맞춘다.
      expect(controller.noticeDaysBefore, 14);
      expect(controller.isNoticeValid, isTrue);
    });

    test('안내 시점 후보는 보관 기간보다 짧을 때만 유효하다', () async {
      final controller = DataRetentionController(_FakeDataRetentionRepository());
      await controller.load(); // 180일
      controller.setRetentionDays(30);

      expect(controller.isNoticeOptionEnabled(7), isTrue);
      expect(controller.isNoticeOptionEnabled(14), isTrue);
      expect(controller.isNoticeOptionEnabled(30), isFalse);
    });

    test('조회값이 프리셋에 없으면 후보 목록에 그 값을 더한다', () async {
      final controller = DataRetentionController(
        _FakeDataRetentionRepository(
          policy: const DataRetentionPolicyDto(
            retentionDays: 200,
            noticeDaysBefore: 45,
            policyStatus: 'PROVISIONAL',
          ),
        ),
      );

      await controller.load();

      expect(controller.retentionOptions, contains(200));
      expect(controller.noticeOptions, contains(45));
    });

    test('저장하면 현재 값을 보내고 dirty가 풀린다', () async {
      final repository = _FakeDataRetentionRepository();
      final controller = DataRetentionController(repository);
      await controller.load();
      controller.setRetentionDays(90);

      final succeeded = await controller.save();

      expect(succeeded, isTrue);
      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.retentionDays, 90);
      expect(repository.updateCalls.single.noticeDaysBefore, 30);
      expect(controller.isDirty, isFalse);
      expect(controller.canSave, isFalse);
    });

    test('180일 보관에서 30일 전은 유효하고 선택할 수 있다', () async {
      final controller = DataRetentionController(_FakeDataRetentionRepository());
      await controller.load(); // 180 / 30

      // 로드 직후 이미 30일 전이 선택돼 있고 유효하다.
      expect(controller.noticeDaysBefore, 30);
      expect(controller.isNoticeOptionEnabled(30), isTrue);

      // 14일 전으로 바꿨다가 다시 30일 전을 골라도 선택된다.
      controller.setNoticeDaysBefore(14);
      expect(controller.noticeDaysBefore, 14);
      controller.setNoticeDaysBefore(30);
      expect(controller.noticeDaysBefore, 30);
    });

    test('보관을 줄여 비활성됐던 30일 전은 보관을 늘리면 다시 선택된다', () async {
      final controller = DataRetentionController(_FakeDataRetentionRepository());
      await controller.load(); // 180 / 30

      controller.setRetentionDays(30); // 30일 전 무효 → 14로 이동
      expect(controller.isNoticeOptionEnabled(30), isFalse);
      expect(controller.noticeDaysBefore, 14);

      controller.setRetentionDays(180); // 다시 늘림
      expect(controller.isNoticeOptionEnabled(30), isTrue);
      controller.setNoticeDaysBefore(30);
      expect(controller.noticeDaysBefore, 30);
    });

    test('저장에 실패하면 dirty를 유지하고 실패 문구를 노출한다', () async {
      final controller = DataRetentionController(
        _FakeDataRetentionRepository(updateError: Exception('save failed')),
      );
      await controller.load();
      controller.setRetentionDays(90);

      final succeeded = await controller.save();

      expect(succeeded, isFalse);
      expect(controller.isDirty, isTrue);
      expect(controller.saveFailureMessage, isNotNull);
    });
  });
}

class _FakeDataRetentionRepository implements DataRetentionRepository {
  _FakeDataRetentionRepository({this.policy, this.loadError, this.updateError});

  final DataRetentionPolicyDto? policy;
  final Object? loadError;
  final Object? updateError;
  final List<({int retentionDays, int noticeDaysBefore})> updateCalls = [];

  @override
  Future<DataRetentionPolicyDto> getDataRetentionPolicy() async {
    if (loadError != null) throw loadError!;
    return policy ??
        const DataRetentionPolicyDto(
          retentionDays: 180,
          noticeDaysBefore: 30,
          policyStatus: 'PROVISIONAL',
        );
  }

  @override
  Future<DataRetentionPolicyDto> updateDataRetentionPolicy({
    required int retentionDays,
    required int noticeDaysBefore,
  }) async {
    updateCalls.add((
      retentionDays: retentionDays,
      noticeDaysBefore: noticeDaysBefore,
    ));
    if (updateError != null) throw updateError!;
    return DataRetentionPolicyDto(
      retentionDays: retentionDays,
      noticeDaysBefore: noticeDaysBefore,
      policyStatus: 'PROVISIONAL',
    );
  }
}
