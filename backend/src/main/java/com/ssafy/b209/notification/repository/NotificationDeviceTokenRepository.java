package com.ssafy.b209.notification.repository;

import com.ssafy.b209.notification.domain.NotificationDeviceToken;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 기기 Token의 설치 식별자 기반 upsert와 Token 재사용 탐지를 담당한다. */
public interface NotificationDeviceTokenRepository
    extends JpaRepository<NotificationDeviceToken, Long> {

  /**
   * 같은 사용자의 같은 설치 식별자 행을 찾는다. 갱신 대상 판별에 사용한다.
   *
   * @param userId 소유 사용자 ID
   * @param deviceId 클라이언트 설치 식별자
   * @return 존재하면 해당 기기 Token
   */
  Optional<NotificationDeviceToken> findByUserIdAndDeviceId(Long userId, String deviceId);

  /**
   * 같은 Token hash를 가진 행을 찾는다. 다른 계정에 이미 등록된 Token을 걸러낸다.
   *
   * @param tokenHash Token SHA-256 hash
   * @return 존재하면 해당 기기 Token
   */
  Optional<NotificationDeviceToken> findByTokenHash(String tokenHash);
}
