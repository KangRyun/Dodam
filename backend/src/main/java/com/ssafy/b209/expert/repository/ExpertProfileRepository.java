package com.ssafy.b209.expert.repository;

import com.ssafy.b209.expert.domain.ExpertProfile;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 사용자별 단일 전문가 프로필을 저장하고 조회한다.
 *
 * <p>전문 분야는 {@link ExpertProfile}의 Cascade 경계 안에서 함께 저장한다.
 */
public interface ExpertProfileRepository
    extends JpaRepository<ExpertProfile, Long>, JpaSpecificationExecutor<ExpertProfile> {

  /**
   * 사용자의 전문가 프로필 존재 여부를 확인한다.
   *
   * @param userId 사용자 식별자
   * @return 프로필이 있으면 {@code true}
   */
  boolean existsByUserId(Long userId);

  /**
   * 전문 분야를 포함한 전문가 상세 프로필을 조회한다.
   *
   * @param expertId 전문가 프로필 식별자
   * @return 프로필이 없으면 빈 값
   */
  @EntityGraph(attributePaths = "specialties")
  @Query("select profile from ExpertProfile profile where profile.id = :expertId")
  Optional<ExpertProfile> findDetailById(@Param("expertId") Long expertId);

  /**
   * 여러 전문가의 팔로워 수와 현재 사용자의 팔로우 여부를 한 번에 조회한다.
   *
   * @param expertIds 전문가 프로필 식별자 목록
   * @param currentUserId 현재 사용자 식별자
   * @return 전문가별 팔로우 요약
   */
  @Query(
      value =
          """
          SELECT ep.id AS expertId,
                 (SELECT COUNT(*) FROM expert_follows ef
                   WHERE ef.expert_profile_id = ep.id) AS followerCount,
                 EXISTS(
                   SELECT 1 FROM expert_follows mine
                    WHERE mine.expert_profile_id = ep.id
                      AND mine.guardian_user_id = :currentUserId
                 ) AS followedByMe
            FROM expert_profiles ep
           WHERE ep.id IN (:expertIds)
          """,
      nativeQuery = true)
  List<ExpertFollowSummary> findFollowSummaries(
      @Param("expertIds") Collection<Long> expertIds, @Param("currentUserId") Long currentUserId);
}
