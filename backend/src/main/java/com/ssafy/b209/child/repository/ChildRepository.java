package com.ssafy.b209.child.repository;

import com.ssafy.b209.child.domain.Child;
import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 그림 활동에서 참조하는 아동을 조회하고 동시 생성 요청을 직렬화하는 저장소다. */
public interface ChildRepository extends JpaRepository<Child, Long> {

  /**
   * 요청 보호자에게 연결된 활성 아동의 상세 프로필을 조회한다.
   *
   * <p>아동 존재 여부, Soft Delete와 보호자 소유권을 한 Query에서 확인해 접근 권한이 없는 호출에 식별자 존재 여부를 노출하지 않는다.
   *
   * @param guardianUserId 조회를 요청한 보호자 사용자 식별자
   * @param childId 조회할 아동 식별자
   * @return 조회 가능한 아동 상세 Projection, 없으면 빈 값
   */
  @Query(
      value =
          """
          select c.id as childId,
                 c.nickname as nickname,
                 c.birth_date as birthDate,
                 c.profile_image_url as profileImageUrl,
                 c.preferred_character as preferredCharacter,
                 c.question_difficulty as questionDifficulty,
                 c.tutorial_status as tutorialStatus,
                 c.profile_status as profileStatus,
                 relation.relationship_type as relationshipType,
                 c.created_at as createdAt,
                 c.updated_at as updatedAt
            from children c
            join guardian_child_relations relation on relation.child_id = c.id
           where c.id = :childId
             and relation.guardian_user_id = :guardianUserId
             and c.deleted_at is null
             and c.profile_status = 'ACTIVE'
          """,
      nativeQuery = true)
  Optional<ChildDetailProjection> findDetailByGuardianUserIdAndChildId(
      @Param("guardianUserId") Long guardianUserId, @Param("childId") Long childId);

  /**
   * 아동 응답 방식을 보호자가 지정한 표시 순서로 조회한다.
   *
   * @param childId 응답 방식을 조회할 아동 식별자
   * @return 표시 순서와 식별자 순서가 적용된 응답 방식 이름
   */
  @Query(
      value =
          """
          select response_mode
            from child_response_modes
           where child_id = :childId
           order by display_order, id
          """,
      nativeQuery = true)
  List<String> findResponseModesByChildId(@Param("childId") Long childId);

  /**
   * 삭제되지 않은 아동을 쓰기 잠금과 함께 조회한다.
   *
   * @param childId 잠글 아동 식별자
   * @return 삭제되지 않은 아동, 존재하지 않으면 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("select c from Child c where c.id = :childId and c.deletedAt is null")
  Optional<Child> findNotDeletedByIdForUpdate(@Param("childId") Long childId);
}
