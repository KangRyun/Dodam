package com.ssafy.b209.consent.repository;

import com.ssafy.b209.consent.domain.ConsentAction;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import java.time.LocalDateTime;

/**
 * 동의 이력과 당시 버전 약관 정보를 결합한 조회 결과다.
 *
 * @param consentRecordId 동의 이력 식별자
 * @param termId 버전 약관 식별자
 * @param termCode 약관 코드
 * @param targetScope 약관 적용 대상
 * @param required 필수 약관 여부
 * @param version 약관 버전
 * @param title 약관 제목
 * @param childId 아동 대상 식별자
 * @param action 동의 행위
 * @param recordedAt 기록 시각
 */
public record ConsentHistoryRow(
    Long consentRecordId,
    Long termId,
    String termCode,
    ConsentTargetScope targetScope,
    boolean required,
    String version,
    String title,
    Long childId,
    ConsentAction action,
    LocalDateTime recordedAt) {}
