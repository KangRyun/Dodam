package com.ssafy.b209.consent.repository;

import com.ssafy.b209.consent.domain.ConsentAction;
import java.time.LocalDateTime;

/**
 * 특정 약관에 대한 가장 최근 동의 행위의 읽기 전용 결과다.
 *
 * @param termId 약관 식별자
 * @param action 가장 최근 동의 또는 철회 행위
 * @param recordedAt 가장 최근 행위 기록 시각
 */
public record LatestConsentAction(Long termId, ConsentAction action, LocalDateTime recordedAt) {}
