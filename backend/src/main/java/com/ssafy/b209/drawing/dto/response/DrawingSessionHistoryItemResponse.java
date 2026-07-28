package com.ssafy.b209.drawing.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.report.domain.ReportStatus;
import java.time.Instant;
import java.util.List;

/**
 * 보호자 활동 기록 목록의 그림 활동 한 건을 요약해 반환한다.
 *
 * <p>연관 리소스가 없으면 해당 값은 {@code null}이며 선택 감정은 빈 목록이다. 아동이 직접 선택한 감정만 포함하고 AI 추정 감정·위험도·전문가 전용 정보는
 * 포함하지 않는다.
 *
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param thumbnailUrl JWT 인증이 필요한 미리보기 상대 URL. 별도 썸네일이 없으면 최신 FINAL 그림을 가리키며, 그림 파일이 없으면 {@code
 *     null}
 * @param drawingType 선택한 그림 활동 유형
 * @param title 아동이 정한 그림 제목, 미작성 시 {@code null}
 * @param inputMethod 그림 입력 방식
 * @param sessionStatus 세션 처리 상태
 * @param currentStage 현재 활동 단계
 * @param selectedEmotions 아동이 선택한 순서의 감정 목록
 * @param analysisStatus 최신 분석 처리 상태, 분석이 없으면 {@code null}
 * @param reportId 최신 리포트 식별자, 없으면 {@code null}
 * @param reportStatus 최신 리포트 상태, 없으면 {@code null}
 * @param startedAt 세션 시작 시각
 * @param completedAt 세션 완료 시각, 완료 전이면 {@code null}
 */
public record DrawingSessionHistoryItemResponse(
    Long drawingSessionId,
    String thumbnailUrl,
    DrawingTypeSummaryResponse drawingType,
    String title,
    DrawingInputMethod inputMethod,
    DrawingSessionStatus sessionStatus,
    DrawingStage currentStage,
    List<DrawingEmotionCode> selectedEmotions,
    DrawingAnalysisStatus analysisStatus,
    Long reportId,
    ReportStatus reportStatus,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant startedAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant completedAt) {

  /** 응답의 선택 감정 목록을 외부에서 변경할 수 없도록 복사한다. */
  public DrawingSessionHistoryItemResponse {
    selectedEmotions = List.copyOf(selectedEmotions);
  }
}
