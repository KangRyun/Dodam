package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 그림 활동의 객관적 사실 기록을 반환한다.
 *
 * <p>모든 수치는 해석을 배제한 객관적 기록이며, 감정 추정이나 위험도 등 판단성 값은 포함하지 않는다.
 *
 * @param detectedObjects 최신 리포트는 VLM 관찰 서술 기반으로 저장한 그린 것 이름 목록이며, 과거 리포트만 0.50 이상 YOLO 탐지 객체명 폴백
 * @param drawingDurationMs 그림 활동 시간(ms)이며 미집계면 {@code null}
 * @param pauseCount 일시 정지 횟수이며 미집계면 {@code null}
 * @param eraseCount 지우기 횟수이며 미집계면 {@code null}
 * @param pressureAvailable 필압 데이터 존재 여부
 * @param notes 객관적 활동 주의사항 목록
 */
@Schema(description = "활동 사실 기록")
public record ReportActivityFactsResponse(
    List<String> detectedObjects,
    Long drawingDurationMs,
    Integer pauseCount,
    Integer eraseCount,
    boolean pressureAvailable,
    List<String> notes) {}
