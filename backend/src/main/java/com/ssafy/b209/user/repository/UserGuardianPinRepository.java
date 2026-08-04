package com.ssafy.b209.user.repository;

import com.ssafy.b209.user.domain.UserGuardianPin;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 보호자 PIN 조회·저장 경계다 (S15P11B209-879). */
public interface UserGuardianPinRepository extends JpaRepository<UserGuardianPin, Long> {

  /**
   * 검증·변경처럼 실패 횟수와 잠금을 함께 바꾸는 경로에서 쓰는 잠금 조회다.
   *
   * <p>행 단위 배타 락으로 동시 요청을 직렬화한다. 락 없이 읽고 쓰면 두 요청이 같은 실패 횟수를 읽어 각자 +1 해서 저장하고, 실패 한 번이 사라진다. 5회 상한이
   * 있는 잠금에서 그 유실은 곧 시도 횟수를 늘려 주는 것이다.
   *
   * <p>잠금 상태는 Redis 가 아니라 DB 를 권위 저장소로 둔다. Redis 를 비우거나 잃어도 잠금이 살아 있어야 한다.
   *
   * @param userId 보호자 사용자 ID
   * @return 존재하면 잠금을 획득한 PIN
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("select pin from UserGuardianPin pin where pin.userId = :userId")
  Optional<UserGuardianPin> findByUserIdForUpdate(@Param("userId") Long userId);
}
