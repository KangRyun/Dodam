package com.ssafy.b209.auth.filter;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Access Token Filter의 단계적 전환 설정이다.
 *
 * @param legacyHeaderEnabled 테스트 환경에서 기존 임시 보호자 Header 요청을 허용할지 여부
 */
@ConfigurationProperties("app.auth.filter")
public record AuthFilterProperties(boolean legacyHeaderEnabled) {}
