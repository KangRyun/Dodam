import '../../../../core/network/network.dart';
import '../../../child/data/dto/child_consent_dtos.dart';
import '../../domain/repositories/consent_repository.dart';
import '../dto/consent_status_dtos.dart';

/// 공개 API(`/consents`)로 동의 현황을 조회하고 선택 동의를 변경한다.
final class RemoteConsentRepository implements ConsentRepository {
  const RemoteConsentRepository(this._apiClient);

  final ApiClient _apiClient;

  /// CONSENT-01 `GET /consents/terms`.
  ///
  /// [scope]가 `null`이면 `targetScope`를 아예 보내지 않는다. 서버가 그 Query를
  /// 선택값으로 두고 없으면 범위 필터를 걸지 않아, 한 번의 호출로 USER·CHILD
  /// 약관을 모두 받는다. 빈 문자열을 보내면 Enum 변환 400이 되므로 키 자체를
  /// 뺀다.
  @override
  Future<List<ConsentTermDto>> getTerms([ConsentTargetScope? scope]) async {
    final response = await _apiClient.get<Object?>(
      'consents/terms',
      queryParameters: {'targetScope': ?scope?.wire},
    );
    return envelopeList(response.data)
        .map((item) => ConsentTermDto.fromJson(jsonObject(item)))
        .toList(growable: false);
  }

  @override
  Future<ConsentStatusDto> getStatus({int? childId}) async {
    final response = await _apiClient.get<Object?>(
      'consents',
      queryParameters: {'childId': ?childId},
    );
    return ConsentStatusDto.fromJson(envelopeObject(response.data));
  }

  @override
  Future<void> changeOptional({
    int? childId,
    required List<ConsentAgreementDto> agreements,
  }) async {
    if (agreements.isEmpty) return;
    await _apiClient.patch<Object?>(
      'consents',
      data: {
        'childId': ?childId,
        'agreements': agreements
            .map((agreement) => agreement.toJson())
            .toList(growable: false),
      },
    );
  }
}
