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
  default boolean hasGuardianChildRelation(Long guardianUserId, Long childId) {
    return countGuardianChildRelation(guardianUserId, childId) > 0L;
  }

  /**
   * 보호자-아동 관계 행 수를 센다.
   *
   * <p>네이티브 {@code exists(...)}는 MySQL에서 BIGINT(0/1)를 돌려주어 Spring Data가 {@code boolean}으로 매핑할 때
   * ClassCastException을 일으키므로, {@code count(*)}로 조회해 {@code long}으로 안전하게 매핑한 뒤 비교한다.
   *
   * @param guardianUserId 보호자 식별자
   * @param childId 아동 식별자
   * @return 관계 행 수(0 또는 1)
   */
  @Query(
      value =
          "select count(*) from guardian_child_relations where guardian_user_id = :guardianUserId and child_id = :childId",
      nativeQuery = true)
  long countGuardianChildRelation(
      @Param("guardianUserId") Long guardianUserId, @Param("childId") Long childId);

  /**
   * 모든 활성 필수 아동 약관({@code target_scope = 'CHILD'})의 최신 아동 동의가 AGREE인지 확인한다.
   *
   * @param childId 동의 대상 아동 식별자
   * @return 필수 동의가 모두 충족되면 {@code true}
   */
  default boolean hasRequiredConsents(Long childId) {
    return countUnsatisfiedRequiredConsents(childId) == 0L;
  }

  /**
   * 최신 아동 동의가 AGREE가 아닌 활성 필수 아동 약관의 수를 센다.
   *
   * <p>네이티브 {@code not exists(...)}의 boolean 매핑 문제를 피하려 미충족 약관 수를 {@code count(*)}로 조회한다. 결과가
   * {@code 0}이면 모든 필수 동의가 충족된 것이다.
   *
   * <p>{@code target_scope = 'CHILD'}로 아동 약관만 센다. USER-scope 약관(예: SERVICE_TOS)은 보호자 계정 동의로 온보딩에서
   * 확인되며 {@code subject_child_id} 이력이 생길 수 없어, 필터가 없으면 어떤 아동도 충족할 수 없는 약관이 되어 대화가 영구 차단된다.
   *
   * @param childId 동의 대상 아동 식별자
   * @return 최신 동의가 AGREE가 아닌 필수·활성 아동 약관 수
   */
  @Query(
      value =
          "select count(*) from consent_terms t where t.is_required = true and t.is_active = true and t.target_scope = 'CHILD' and not exists (select 1 from consent_records r where r.consent_term_id = t.id and r.subject_child_id = :childId and r.recorded_at = (select max(r2.recorded_at) from consent_records r2 where r2.consent_term_id = t.id and r2.subject_child_id = :childId) and r.action = 'AGREE')",
      nativeQuery = true)
  long countUnsatisfiedRequiredConsents(@Param("childId") Long childId);
}
