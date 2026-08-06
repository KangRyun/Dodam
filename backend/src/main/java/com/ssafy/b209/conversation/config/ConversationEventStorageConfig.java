package com.ssafy.b209.conversation.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * 대화 행동 이벤트 저장소 설정을 활성화한다 (S15P11B209-973).
 *
 * <p>MongoDB 연결 자체는 Spring Boot 자동 설정이 담당하고, 여기서는 애플리케이션이 정하는 값(보관 기간)만 Binding한다.
 */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(ConversationEventRetentionProperties.class)
public class ConversationEventStorageConfig {}
