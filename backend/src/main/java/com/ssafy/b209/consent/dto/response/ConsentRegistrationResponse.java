package com.ssafy.b209.consent.dto.response;

import java.time.LocalDateTime;

/**
 * append-only 동의 이력의 최초 등록 결과다.
 *
 * @param childId 아동 대상 등록이면 아동 ID, 사용자 대상만 등록하면 {@code null}
 * @param recordedCount 새로 저장한 동의 이력 수
 * @param requiredConsentsSatisfied 현재 요청이 필수 약관을 모두 동의했는지 여부
 * @param recordedAt 서버가 모든 이력에 공통으로 기록한 시각
 */
public record ConsentRegistrationResponse(
    Long childId, int recordedCount, boolean requiredConsentsSatisfied, LocalDateTime recordedAt) {}
