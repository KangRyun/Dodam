package com.ssafy.b209.report.domain;

/**
 * 리포트 생성 상태다.
 *
 * <p><strong>활동 상태와 다른 값이다.</strong> 아이가 그림을 그리고 마음을 고르고 대화를 마쳤으면 그 활동은 끝난 것이고, 리포트는 그 기록을 읽어 만드는
 * 별개의 일이다. 예전에는 이 값이 실패하면 그림 세션까지 {@code FAILED}로 내려가 아이 화면에 "활동을 마무리하지 못했어요"가 떴다(2026-08-08 실측).
 */
public enum ReportStatus {
  /** 생성 중이다. */
  GENERATING,

  /** 보호자에게 보여 줄 수 있다. */
  COMPLETED,

  /**
   * 실패했으나 재시도 판단이 없는 옛 값이다.
   *
   * <p>활동·리포트를 떼어 놓기 전에 생긴 행이 이 값으로 남아 있다. 어느 쪽이었는지 지금 와서는 알 수 없어 새로 쓰지 않는다 — 읽는 쪽은 '재시도 판단 불가'로
   * 다룬다.
   */
  FAILED,

  /** 상류 장애·타임아웃처럼 다시 하면 될 수 있는 실패다. 재시도 대기열에 오른다. */
  FAILED_RETRYABLE,

  /** 근거 부족·응답 계약 위반처럼 다시 해도 같은 실패다. 재시도하지 않는다. */
  FAILED_FINAL,

  /** 보호자에게 숨긴 리포트다. */
  HIDDEN;

  /**
   * @return 어떤 형태로든 실패한 상태면 {@code true}
   */
  public boolean isFailure() {
    return this == FAILED || this == FAILED_RETRYABLE || this == FAILED_FINAL;
  }

  /**
   * @return 다시 만들어 볼 값어치가 있는 실패면 {@code true}
   */
  public boolean isRetryableFailure() {
    return this == FAILED_RETRYABLE;
  }
}
