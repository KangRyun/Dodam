package com.ssafy.b209.drawing.htp.dto;

import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStatus;
import com.ssafy.b209.report.domain.ReportStatus;

/**
 * HTP 세 단계 결과를 단일 리포트로 생성하는 비동기 작업의 접수 상태다.
 *
 * @param htpAssessmentId HTP 활동 묶음 식별자
 * @param status HTP 종합 처리 상태
 * @param analysisId 리포트 생성 작업을 추적하는 분석 식별자
 * @param analysisStatus 분석 작업 상태
 * @param reportId HTP 묶음의 단일 리포트 식별자
 * @param reportStatus 리포트 생성 상태
 */
public record HtpCompletionResponse(
    Long htpAssessmentId,
    HtpAssessmentStatus status,
    Long analysisId,
    DrawingAnalysisState analysisStatus,
    Long reportId,
    ReportStatus reportStatus) {}
