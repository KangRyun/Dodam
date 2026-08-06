package com.ssafy.b209.conversation.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * 대화 진행 정책 설정을 활성화한다 (S15P11B209-976).
 *
 * <p>대화가 몇 번 물을지는 클라이언트가 아니라 서버가 정한다. 그 값을 코드 상수가 아니라 환경 설정에 두어, 운영 실측을 보고 배포 없이 조정할 수 있게 한다.
 */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(ConversationQuestionLimitProperties.class)
public class ConversationQuestionPolicyConfig {}
