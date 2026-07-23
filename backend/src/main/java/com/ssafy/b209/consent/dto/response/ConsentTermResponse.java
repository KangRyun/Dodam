package com.ssafy.b209.consent.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import java.time.Instant;

/**
 * 현재 적용 중인 버전 약관의 공개 표현이다.
 *
 * @param termId 약관 식별자
 * @param termCode 약관 코드
 * @param targetScope 동의 적용 범위
 * @param required 서비스 이용 필수 여부
 * @param version 약관 버전
 * @param title 약관 제목
 * @param contentUrl 약관 원문 URL, 없으면 {@code null}
 * @param effectiveAt 약관 시행 시각
 */
public record ConsentTermResponse(
    Long termId,
    String termCode,
    ConsentTargetScope targetScope,
    boolean required,
    String version,
    String title,
    String contentUrl,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant effectiveAt) {}
