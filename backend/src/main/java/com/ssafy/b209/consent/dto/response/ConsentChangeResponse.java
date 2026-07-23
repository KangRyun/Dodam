package com.ssafy.b209.consent.dto.response;

import java.time.LocalDateTime;

/**
 * 선택 약관 변경으로 새로 기록된 동의 이력의 처리 결과다.
 *
 * @param childId 아동 대상 약관을 포함한 요청의 아동 ID, 사용자 약관만 변경하면 {@code null}
 * @param recordedCount 새로 추가된 동의 이력 수
 * @param recordedAt 동의 변경 이력을 기록한 시각
 */
public record ConsentChangeResponse(Long childId, int recordedCount, LocalDateTime recordedAt) {}
