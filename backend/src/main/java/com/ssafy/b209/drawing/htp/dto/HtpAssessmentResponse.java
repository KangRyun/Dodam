package com.ssafy.b209.drawing.htp.dto;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStatus;
import java.time.Instant;

/**
 * HTP 묶음 상태와 현재 그림 단계를 반환한다.
 *
 * @param htpAssessmentId HTP 활동 묶음 식별자
 * @param status 묶음 처리 상태
 * @param expiresAt 재개 가능한 만료 시각
 * @param currentStep 현재 또는 마지막 그림 단계
 * @param allStepsCompleted HOUSE, TREE, PERSON 세 단계가 모두 완료됐는지 여부
 */
public record HtpAssessmentResponse(
    Long htpAssessmentId,
    HtpAssessmentStatus status,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant expiresAt,
    HtpAssessmentStepResponse currentStep,
    boolean allStepsCompleted) {}
