package com.ssafy.b209.child.repository;

import com.ssafy.b209.child.domain.Child;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 그림 활동에서 참조하는 아동을 조회하고 동시 생성 요청을 직렬화하는 저장소다. */
public interface ChildRepository extends JpaRepository<Child, Long> {

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
