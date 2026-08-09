import '../../../../core/network/network.dart';
import '../../domain/repositories/referral_summary_repository.dart';
import '../dto/referral_summary_dto.dart';

/// `GET /children/{childId}/referral-summary` 를 호출한다 (S15P11B209-1012).
final class RemoteReferralSummaryRepository
    implements ReferralSummaryRepository {
  const RemoteReferralSummaryRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ReferralSummaryDto> getReferralSummary(
    int childId, {
    int? sessions,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'children/$childId/referral-summary',
      queryParameters: sessions == null ? null : {'sessions': sessions},
    );
    return ReferralSummaryDto.fromJson(envelopeObject(response.data));
  }
}
