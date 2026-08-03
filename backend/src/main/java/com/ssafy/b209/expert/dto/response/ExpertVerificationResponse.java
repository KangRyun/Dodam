package com.ssafy.b209.expert.dto.response;

import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import java.time.Instant;
import java.util.List;

/**
 * 관리자 검토로 확정된 전문가 프로필과 자격 상태를 반환한다.
 *
 * @param expertId 전문가 프로필 식별자
 * @param verificationStatus 프로필 최종 검증 상태
 * @param credentials 프로필에 속한 자격별 현재 상태
 * @param reviewedAt 서버 기준 검토 완료 시각
 */
public record ExpertVerificationResponse(
    Long expertId,
    ExpertVerificationStatus verificationStatus,
    List<CredentialStatus> credentials,
    Instant reviewedAt) {

  /**
   * 검토 후 자격 한 건의 상태다.
   *
   * @param credentialId 자격 식별자
   * @param verificationStatus 자격 검증 상태
   */
  public record CredentialStatus(Long credentialId, ExpertVerificationStatus verificationStatus) {}
}
