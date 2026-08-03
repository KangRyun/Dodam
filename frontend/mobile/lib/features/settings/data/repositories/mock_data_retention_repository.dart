import '../../domain/repositories/data_retention_repository.dart';
import '../dto/data_retention_dtos.dart';

/// 백엔드 미연결 개발·데모·테스트용 목 구현.
///
/// 계약 기본값(180·30)을 조회로 돌려주고, 수정은 받은 값을 그대로 되돌려 준다
/// (저장 상태를 들지 않아 `const`로 둘 수 있다). 실제 저장·검증은 서버 몫이라
/// 여기서 재현하지 않는다.
final class MockDataRetentionRepository implements DataRetentionRepository {
  const MockDataRetentionRepository();

  @override
  Future<DataRetentionPolicyDto> getDataRetentionPolicy() async =>
      const DataRetentionPolicyDto(
        retentionDays: 180,
        noticeDaysBefore: 30,
        policyStatus: 'PROVISIONAL',
      );

  @override
  Future<DataRetentionPolicyDto> updateDataRetentionPolicy({
    required int retentionDays,
    required int noticeDaysBefore,
  }) async => DataRetentionPolicyDto(
    retentionDays: retentionDays,
    noticeDaysBefore: noticeDaysBefore,
    policyStatus: 'PROVISIONAL',
  );
}
