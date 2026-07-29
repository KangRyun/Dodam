package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;
import java.time.Instant;
import java.util.List;

/**
 * HTP 원본 이미지의 저장 결과와 다음 완료 요청에 사용할 참조값을 제공한다.
 *
 * @param drawingSessionId 이미지가 속한 HTP 단계 세션 식별자
 * @param drawingAssetId 완료 요청의 {@code sourceAssetId}로 사용할 그림 파일 식별자
 * @param assetType 저장된 파일 유형
 * @param drawingSubject 서버가 HTP 단계에서 확정한 주제
 * @param currentStage 업로드 후 유지되는 현재 단계
 * @param previewUrl Access Token으로 조회하는 이미지 상대 URL
 * @param mimeType 파일 Signature로 확정한 MIME Type
 * @param fileSizeBytes 정규화 후 저장된 파일 크기
 * @param widthPx 저장 이미지의 실제 너비
 * @param heightPx 저장 이미지의 실제 높이
 * @param capturedAt 클라이언트 촬영 시각 또는 서버 수신 시각
 * @param uploadedAt 서버 저장 완료 시각
 * @param qualityWarnings 서버가 확인한 비차단 품질 경고
 */
public record UploadDrawingImageResponse(
    Long drawingSessionId,
    Long drawingAssetId,
    DrawingAssetType assetType,
    HtpDrawingSubject drawingSubject,
    DrawingStage currentStage,
    String previewUrl,
    String mimeType,
    long fileSizeBytes,
    Integer widthPx,
    Integer heightPx,
    Instant capturedAt,
    Instant uploadedAt,
    List<String> qualityWarnings) {}
