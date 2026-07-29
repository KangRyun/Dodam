package com.ssafy.b209.analysis.dto;

import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import java.util.Objects;

/** 기존 세션 하위 그림 분석 API가 호환 목적으로 사용하는 처리 상태를 나타낸다. */
public enum DrawingAnalysisStatus {
  /** 분석 요청이 대기 중인 상태다. */
  PENDING,
  /** AI 서버가 분석을 수행 중인 상태다. */
  PROCESSING,
  /** 분석이 정상적으로 완료된 상태다. */
  SUCCEEDED,
  /** 분석을 완료하지 못한 상태다. */
  FAILED;

  /**
   * DB에 저장된 도메인 분석 상태를 외부 계약 상태로 변환한다.
   *
   * <p>저장 상태 {@code SUCCESS}는 {@code SUCCEEDED}로 노출한다. 일부 단계만 성공한 {@code PARTIAL_SUCCESS}도 기존
   * Client 호환을 위해 {@code SUCCEEDED}로 노출한다. 정본 {@code /api/v1/analyses/{analysisId}} 조회는 이 변환을 사용하지
   * 않는다.
   *
   * @param state DB에 저장된 도메인 분석 상태
   * @return 외부 계약에서 사용하는 분석 상태
   */
  public static DrawingAnalysisStatus from(DrawingAnalysisState state) {
    Objects.requireNonNull(state, "state must not be null");
    return switch (state) {
      case PENDING -> PENDING;
      case PROCESSING -> PROCESSING;
      case SUCCESS, PARTIAL_SUCCESS -> SUCCEEDED;
      case FAILED -> FAILED;
    };
  }
}
