package com.ssafy.b209.auth.service;

import java.time.Duration;

/** Refresh Token 원문 없이 사용자·기기별 rotation 세션을 저장하는 외부 저장소 추상화다. */
public interface RefreshTokenSessionStore {

  /**
   * 최초 로그인에서 발급한 Refresh Token hash를 새 family 세션으로 저장한다.
   *
   * @param familyId Token에 포함된 임의 family 식별자
   * @param userId 인증 사용자 ID
   * @param deviceId 로그인 요청의 기기 식별자
   * @param tokenHash Refresh Token의 SHA-256 hash
   * @param ttl Refresh Token과 동일한 세션 만료 시간
   */
  void register(String familyId, Long userId, String deviceId, String tokenHash, Duration ttl);

  /**
   * 현재 Token hash를 비교하고 일치할 때만 새 hash로 원자적으로 교체한다.
   *
   * @param familyId Token family 식별자
   * @param userId Refresh JWT Subject
   * @param deviceId 재발급 요청 기기 식별자
   * @param currentTokenHash 요청 Token의 SHA-256 hash
   * @param newTokenHash 새 Refresh Token의 SHA-256 hash
   * @param ttl 새 Refresh Token과 동일한 세션 만료 시간
   * @return rotation 또는 거부 사유
   */
  RefreshTokenRotationResult rotate(
      String familyId,
      Long userId,
      String deviceId,
      String currentTokenHash,
      String newTokenHash,
      Duration ttl);
}
