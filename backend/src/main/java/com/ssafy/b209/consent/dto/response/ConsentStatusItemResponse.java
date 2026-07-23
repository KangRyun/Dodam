package com.ssafy.b209.consent.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import java.time.Instant;

/**
 * 특정 약관에 대한 현재 동의 상태 항목이다.
 *
 * <p>append-only 이력의 가장 최근 행위를 반영하며 아직 처리 이력이 없으면 미동의로 간주한다.
 *
 * @param termId 약관 식별자
 * @param termCode 약관 코드
 * @param required 서비스 이용 필수 여부
 * @param version 약관 버전
 * @param agreed 가장 최근 행위가 동의이면 {@code true}
 * @param recordedAt 가장 최근 처리 시각, 이력이 없으면 {@code null}
 */
public record ConsentStatusItemResponse(
    Long termId,
    String termCode,
    boolean required,
    String version,
    boolean agreed,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant recordedAt) {}
