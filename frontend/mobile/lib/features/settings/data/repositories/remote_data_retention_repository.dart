import '../../../../core/network/network.dart';
import '../../domain/repositories/data_retention_repository.dart';
import '../dto/data_retention_dtos.dart';

/// 데이터 보관 정책 실 API 구현. 응답은 공통 봉투 `{success, code, message, data}`로
/// 오므로 [envelopeObject]로 `data`를 벗겨 파싱한다.
///
/// 계약: `docs/api/data-retention-policy-contract.md`
final class RemoteDataRetentionRepository implements DataRetentionRepository {
  const RemoteDataRetentionRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<DataRetentionPolicyDto> getDataRetentionPolicy() async {
    final response = await _apiClient.get<Object?>('users/me/data-retention');
    return DataRetentionPolicyDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<DataRetentionPolicyDto> updateDataRetentionPolicy({
    required int retentionDays,
    required int noticeDaysBefore,
  }) async {
    final response = await _apiClient.patch<Object?>(
      'users/me/data-retention',
      data: {
        'retentionDays': retentionDays,
        'noticeDaysBefore': noticeDaysBefore,
      },
    );
    return DataRetentionPolicyDto.fromJson(envelopeObject(response.data));
  }
}
