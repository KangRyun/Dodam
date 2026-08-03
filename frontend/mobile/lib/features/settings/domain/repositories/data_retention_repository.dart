import '../../data/dto/data_retention_dtos.dart';

/// 데이터 보관 정책 조회·수정 도메인 계약. 대상 사용자는 Access Token에서
/// 해석하므로 식별자를 받지 않는다(IDOR 차단).
///
/// 계약: `docs/api/data-retention-policy-contract.md`
/// (S15P11B209-564 조회 · S15P11B209-565 수정)
abstract interface class DataRetentionRepository {
  /// `GET /users/me/data-retention` — 설정 행이 없으면 기본값(180·30)을 준다.
  Future<DataRetentionPolicyDto> getDataRetentionPolicy();

  /// `PATCH /users/me/data-retention` — 두 값 전체 교체(upsert).
  ///
  /// 검증 불변식은 서버가 최종 판정하지만(`noticeDaysBefore < retentionDays`
  /// 등) 화면도 같은 조건을 먼저 확인해 무효한 요청을 보내지 않는다.
  Future<DataRetentionPolicyDto> updateDataRetentionPolicy({
    required int retentionDays,
    required int noticeDaysBefore,
  });
}
