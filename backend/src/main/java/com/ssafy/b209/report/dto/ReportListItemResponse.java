package com.ssafy.b209.report.dto;

import com.ssafy.b209.report.domain.ReportStatus;
import java.time.LocalDate;
import java.util.List;

/**
 * 보호자 리포트 목록의 한 항목이다.
 *
 * <p>아동이 직접 선택한 감정만 포함하며 AI가 추정한 감정이나 진단성 정보는 노출하지 않는다.
 *
 * @param reportId 리포트 식별자
 * @param reportVersion 동일 활동에서 증가하는 리포트 버전
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param drawingType 그림 유형 요약
 * @param title 활동 제목이며 없으면 그림 유형 이름
 * @param thumbnailUrl JWT 인증이 필요한 미리보기 상대 URL. 별도 썸네일이 없으면 최신 FINAL 그림을 가리키며, 그림 파일이 없으면 {@code
 *     null}
 * @param activityDate 활동을 시작한 날짜
 * @param durationMs 활동 소요 시간이며 완료 전이면 {@code null}
 * @param selectedEmotions 아동이 직접 선택한 감정 코드
 * @param reportStatus 리포트 생성 상태
 * @param expertReviewAvailable 전문가 검토 결과를 조회할 수 있는지 여부
 */
public record ReportListItemResponse(
    Long reportId,
    int reportVersion,
    Long drawingSessionId,
    ReportListDrawingTypeResponse drawingType,
    String title,
    String thumbnailUrl,
    LocalDate activityDate,
    Long durationMs,
    List<String> selectedEmotions,
    ReportStatus reportStatus,
    boolean expertReviewAvailable) {

  /** 응답 목록이 외부에서 변경되지 않도록 선택 감정 목록을 복사한다. */
  public ReportListItemResponse {
    selectedEmotions = List.copyOf(selectedEmotions);
  }
}
