package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationStartChildProfile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 보호자-아동 관계와 최신 필수 동의 상태를 DB v1.2에서 조회하는 경계다. */
public interface ConversationStartAuthorizationRepository
    extends JpaRepository<ConversationStartChildProfile, Long> {

  /**
   * 지정 보호자가 아동과 연결돼 있는지 확인한다.
   *
   * @param guardianUserId 임시 인증 계층이 제공한 보호자 식별자
   * @param childId 확인할 아동 식별자
   * @return 관계가 존재하면 {@code true}
   */
  @Query(
      value =
          "select exists(select 1 from guardian_child_relations where guardian_user_id = :guardianUserId and child_id = :childId)",
      nativeQuery = true)
  boolean hasGuardianChildRelation(
      @Param("guardianUserId") Long guardianUserId, @Param("childId") Long childId);

  /**
   * 모든 활성 필수 약관의 최신 아동 동의가 AGREE인지 확인한다.
   *
   * @param childId 동의 대상 아동 식별자
   * @return 필수 동의가 모두 충족되면 {@code true}
   */
  @Query(
      value =
          "select not exists (select 1 from consent_terms t where t.is_required = true and t.is_active = true and not exists (select 1 from consent_records r where r.consent_term_id = t.id and r.subject_child_id = :childId and r.recorded_at = (select max(r2.recorded_at) from consent_records r2 where r2.consent_term_id = t.id and r2.subject_child_id = :childId) and r.action = 'AGREE'))",
      nativeQuery = true)
  boolean hasRequiredConsents(@Param("childId") Long childId);
}
