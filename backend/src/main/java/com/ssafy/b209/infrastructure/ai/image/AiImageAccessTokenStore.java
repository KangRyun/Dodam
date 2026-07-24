package com.ssafy.b209.infrastructure.ai.image;

import java.time.Duration;
import java.util.Optional;

/** Storage Key와 짧은 수명의 일회성 이미지 조회 Token을 연결한다. */
public interface AiImageAccessTokenStore {

  /**
   * Storage Key를 지정된 시간 동안 한 번 조회할 수 있는 Token을 발급한다.
   *
   * @param storageKey 이미지 저장 위치를 식별하는 상대 Key
   * @param ttl Token 유효 시간
   * @return 외부에 전달할 불투명 Token
   */
  String issue(String storageKey, Duration ttl);

  /**
   * Token을 원자적으로 소비하고 연결된 Storage Key를 반환한다.
   *
   * @param token 발급된 일회성 Token
   * @return 유효한 최초 요청이면 Storage Key, 아니면 빈 값
   */
  Optional<String> consume(String token);
}
