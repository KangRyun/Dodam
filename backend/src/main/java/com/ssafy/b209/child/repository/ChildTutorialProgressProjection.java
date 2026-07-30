package com.ssafy.b209.child.repository;

import java.time.LocalDateTime;

/**
 * 보호자 소유권이 확인된 아동의 Tutorial 진행 정보를 담는 읽기 전용 Projection이다.
 *
 * <p>조회 Query에서 삭제·비활성 아동과 연결되지 않은 보호자를 제외하므로 Service는 존재 여부를 노출하지 않고 동일한 Not Found 정책을 적용할 수 있다.
 */
public interface ChildTutorialProgressProjection {

  /**
   * 아동 식별자를 반환한다.
   *
   * @return 아동 식별자
   */
  Long getChildId();

  /**
   * Tutorial 상태의 DB 문자열을 반환한다.
   *
   * @return {@code ChildTutorialStatus} Enum 이름
   */
  String getTutorialStatus();

  /**
   * 마지막으로 저장된 Tutorial 단계 식별자를 반환한다.
   *
   * @return 마지막 단계 또는 저장 전이면 {@code null}
   */
  String getLastStep();

  /**
   * Tutorial 완료 또는 건너뛰기 시각을 반환한다.
   *
   * @return 종료 시각 또는 종료 전이면 {@code null}
   */
  LocalDateTime getCompletedAt();

  /**
   * Tutorial 진행 정보의 마지막 변경 시각을 반환한다.
   *
   * @return 마지막 변경 시각
   */
  LocalDateTime getUpdatedAt();
}
