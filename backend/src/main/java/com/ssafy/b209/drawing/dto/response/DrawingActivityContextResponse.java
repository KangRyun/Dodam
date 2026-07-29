package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStatus;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;

/**
 * 진행 중 그림 세션이 속한 활동 묶음 문맥을 반환한다.
 *
 * <p>일반 활동은 {@code activityKind=GENERAL}이며 HTP 전용 필드는 {@code null}이다. HTP는 서버에 저장된 묶음과 현재 단계 정보를
 * 제공해 클라이언트가 주제나 순서를 추론하지 않도록 한다.
 *
 * @param activityKind {@code GENERAL} 또는 {@code HTP}
 * @param htpAssessmentId HTP 묶음 식별자
 * @param htpStatus HTP 묶음 상태
 * @param stepOrder 현재 HTP 단계 순서
 * @param drawingSubject 현재 HTP 그림 주제
 */
public record DrawingActivityContextResponse(
    String activityKind,
    Long htpAssessmentId,
    HtpAssessmentStatus htpStatus,
    Integer stepOrder,
    HtpDrawingSubject drawingSubject) {

  /** 일반 그림 활동 문맥을 생성한다. */
  public static DrawingActivityContextResponse general() {
    return new DrawingActivityContextResponse("GENERAL", null, null, null, null);
  }
}
