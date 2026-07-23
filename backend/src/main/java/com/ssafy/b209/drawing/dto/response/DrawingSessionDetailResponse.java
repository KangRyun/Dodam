package com.ssafy.b209.drawing.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import java.time.Instant;
import java.util.List;

/**
 * 그림 활동의 현재 상태와 화면 이동에 필요한 최신 연관 리소스를 반환한다.
 *
 * <p>연관 리소스가 없으면 해당 요약이나 식별자는 {@code null}이며 선택 감정은 빈 목록이다.
 *
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param child 그림 활동을 수행한 아동 요약
 * @param drawingType 선택한 그림 활동 유형
 * @param inputMethod 그림 입력 방식
 * @param title 아동이 정한 그림 제목, 미작성 시 {@code null}
 * @param selectedEmotions 아동이 선택한 순서의 감정 목록
 * @param sessionStatus 세션 처리 상태
 * @param currentStage 현재 활동 단계
 * @param latestAsset 최신 그림 파일 Metadata, 없으면 {@code null}
 * @param latestAnalysis 최신 분석 실행 Metadata, 없으면 {@code null}
 * @param conversationId 연결된 대화 세션 식별자, 없으면 {@code null}
 * @param reportId 최신 리포트 식별자, 없으면 {@code null}
 * @param startedAt 세션 시작 시각
 * @param completedAt 세션 완료 시각, 완료 전이면 {@code null}
 * @param recoverableDraft 복구 가능한 자동 저장 초안 존재 여부
 */
public record DrawingSessionDetailResponse(
    Long drawingSessionId,
    DrawingSessionChildSummaryResponse child,
    DrawingTypeSummaryResponse drawingType,
    DrawingInputMethod inputMethod,
    String title,
    List<DrawingEmotionCode> selectedEmotions,
    DrawingSessionStatus sessionStatus,
    DrawingStage currentStage,
    DrawingSessionAssetSummaryResponse latestAsset,
    DrawingSessionAnalysisSummaryResponse latestAnalysis,
    Long conversationId,
    Long reportId,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant startedAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant completedAt,
    boolean recoverableDraft) {

  /** 응답의 선택 감정 목록을 외부에서 변경할 수 없도록 복사한다. */
  public DrawingSessionDetailResponse {
    selectedEmotions = List.copyOf(selectedEmotions);
  }
}
