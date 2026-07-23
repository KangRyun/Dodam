package com.ssafy.b209.consent.dto.response;

import com.ssafy.b209.consent.domain.ConsentAction;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * 특정 버전 약관에 대해 기록된 동의 또는 철회 행위 한 건을 반환한다.
 *
 * @param consentRecordId 동의 이력 식별자
 * @param termId 버전 약관 식별자
 * @param termCode 버전이 바뀌어도 유지되는 약관 코드
 * @param targetScope 약관 적용 대상
 * @param required 필수 약관 여부
 * @param version 동의 당시 약관 버전
 * @param title 동의 당시 약관 제목
 * @param childId 아동 대상 약관의 대상 식별자, 사용자 대상 약관이면 {@code null}
 * @param action 기록된 동의 또는 철회 행위
 * @param recordedAt 서버가 행위를 기록한 시각
 */
@Schema(description = "버전별 동의 이력")
public record ConsentHistoryItemResponse(
    Long consentRecordId,
    Long termId,
    String termCode,
    ConsentTargetScope targetScope,
    boolean required,
    String version,
    String title,
    Long childId,
    ConsentAction action,
    Instant recordedAt) {}
