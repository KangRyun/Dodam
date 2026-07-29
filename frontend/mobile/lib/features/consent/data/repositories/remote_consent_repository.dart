import '../../../../core/network/network.dart';
import '../../../child/data/dto/child_consent_dtos.dart';
import '../../domain/repositories/consent_repository.dart';
import '../dto/consent_status_dtos.dart';

/// 공개 API(`/consents`)로 동의 현황을 조회하고 선택 동의를 변경한다.
final class RemoteConsentRepository implements ConsentRepository {
  const RemoteConsentRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<ConsentTermDto>> getTerms(ConsentTargetScope scope) async {
    final response = await _apiClient.get<Object?>(
      'consents/terms',
      queryParameters: {'targetScope': scope.wire},
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
