package com.ssafy.b209.analysis.service;

import java.time.LocalDateTime;

/**
 * 저장을 시작한 분석과 Transaction 밖의 Client 호출에 필요한 최소 이미지 참조를 전달한다.
 *
 * @param analysisId 저장된 분석 실행 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param drawingAssetId 분석 대상 그림 파일 식별자
 * @param requestId 서버가 생성한 Client 요청 UUID
 * @param storageKey 내부 이미지 저장소 상대 Key
 * @param contentType 검증된 이미지 MIME Type
 * @param requestedAt 서버가 분석을 시작한 UTC 시각
 */
public record StartedDrawingAnalysis(
    Long analysisId,
    Long drawingSessionId,
    Long drawingAssetId,
    String requestId,
    String storageKey,
    String contentType,
    LocalDateTime requestedAt) {}
