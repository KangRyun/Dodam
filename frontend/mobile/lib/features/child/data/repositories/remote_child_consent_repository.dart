import '../../../../core/network/network.dart';
import '../../domain/repositories/child_consent_repository.dart';
import '../dto/child_consent_dtos.dart';

/// 공개 API(`/consents`)로 아동 약관을 조회·기록한다.
///
/// 서버는 `childId`가 있으면 아동 범위 약관이 최소 한 건 포함되기를 요구하므로
/// 조회한 CHILD 약관 전체를 그대로 되돌려 보낸다.
final class RemoteChildConsentRepository implements ChildConsentRepository {
  const RemoteChildConsentRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<ConsentTermDto>> getChildTerms() async {
    final response = await _apiClient.get<Object?>(
      'consents/terms',
      queryParameters: const {'targetScope': 'CHILD'},
    );
    return envelopeList(response.data)
        .map((item) => ConsentTermDto.fromJson(jsonObject(item)))
        .toList(growable: false);
  }

  @override
  Future<void> submitChildConsents({
    required int childId,
    required List<ConsentAgreementDto> agreements,
  }) async {
    if (agreements.isEmpty) return;
    await _apiClient.post<Object?>(
      'consents',
      data: {
        'childId': childId,
        'agreements': agreements
            .map((agreement) => agreement.toJson())
            .toList(growable: false),
      },
    );
  }
}
