package com.ssafy.b209.analysis.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisTriggerReason;
import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.dto.DrawingAnalysisSubject;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import java.time.LocalDateTime;

/**
 * 저장을 시작한 분석과 Transaction 밖의 Client 호출에 필요한 최소 이미지 참조를 전달한다.
 *
 * @param analysisId 저장된 분석 실행 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param drawingAssetId 분석 대상 그림 파일 식별자
 * @param requestId 서버가 생성한 Client 요청 UUID
 * @param analysisScope 중간 또는 최종 분석 범위
 * @param activityType 저장된 그림 유형에서 확정한 AI 활동 유형
 * @param drawingSubject 저장된 HTP 단계 주제이며 그림일기는 {@code null}
 * @param inputMethod 그림 세션에 저장된 입력 방식
 * @param triggerReason 저장된 분석 실행 사유
 * @param storageKey 내부 이미지 저장소 상대 Key
 * @param contentType 검증된 이미지 MIME Type
 * @param widthPx 원본 이미지 너비
 * @param heightPx 원본 이미지 높이
 * @param checksumSha256 원본 이미지 SHA-256 Checksum
 * @param requestedAt 서버가 분석을 시작한 UTC 시각
 */
public record StartedDrawingAnalysis(
    Long analysisId,
    Long drawingSessionId,
    Long drawingAssetId,
    String requestId,
    DrawingAnalysisScope analysisScope,
    DrawingAnalysisActivityType activityType,
    DrawingAnalysisSubject drawingSubject,
    DrawingInputMethod inputMethod,
    DrawingAnalysisTriggerReason triggerReason,
    String storageKey,
    String contentType,
    Integer widthPx,
    Integer heightPx,
    String checksumSha256,
    LocalDateTime requestedAt) {

  /** 실행 사유가 생략된 내부 호출에 입력 방식을 명시한다. */
  public StartedDrawingAnalysis(
      Long analysisId,
      Long drawingSessionId,
      Long drawingAssetId,
      String requestId,
      DrawingAnalysisScope analysisScope,
      DrawingAnalysisActivityType activityType,
      DrawingAnalysisSubject drawingSubject,
      DrawingInputMethod inputMethod,
      String storageKey,
      String contentType,
      Integer widthPx,
      Integer heightPx,
      String checksumSha256,
      LocalDateTime requestedAt) {
    this(
        analysisId,
        drawingSessionId,
        drawingAssetId,
        requestId,
        analysisScope,
        activityType,
        drawingSubject,
        inputMethod,
        DrawingAnalysisTriggerReason.USER_REQUEST,
        storageKey,
        contentType,
        widthPx,
        heightPx,
        checksumSha256,
        requestedAt);
  }
}
