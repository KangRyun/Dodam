import '../../data/dto/referral_summary_dto.dart';

/// 전문가 의뢰 요약 조회 경계 (S15P11B209-1012).
abstract interface class ReferralSummaryRepository {
  /// 아이의 의뢰 요약을 가져온다.
  ///
  /// @param childId 대상 아동 식별자
  /// @param sessions 가져올 최근 회차 수이며 없으면 서버 기본값(1~10 사이로 서버가 맞춘다)
  Future<ReferralSummaryDto> getReferralSummary(int childId, {int? sessions});
}
