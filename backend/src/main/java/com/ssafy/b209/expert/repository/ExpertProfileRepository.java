package com.ssafy.b209.expert.repository;

import com.ssafy.b209.expert.domain.ExpertProfile;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 사용자별 단일 전문가 프로필을 저장하고 조회한다.
 *
 * <p>전문 분야는 {@link ExpertProfile}의 Cascade 경계 안에서 함께 저장한다.
 */
public interface ExpertProfileRepository extends JpaRepository<ExpertProfile, Long> {

  /**
   * 사용자의 전문가 프로필 존재 여부를 확인한다.
   *
   * @param userId 사용자 식별자
   * @return 프로필이 있으면 {@code true}
   */
  boolean existsByUserId(Long userId);
}
