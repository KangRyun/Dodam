package com.ssafy.b209.infrastructure.push;

import org.springframework.context.annotation.Condition;
import org.springframework.context.annotation.ConditionContext;
import org.springframework.core.type.AnnotatedTypeMetadata;

/**
 * FCM 발송을 실제로 할 수 있는 환경인지 판정한다 — 스위치가 켜졌고 자격증명도 쓸 수 있어야 한다.
 *
 * <p>{@code @ConditionalOnProperty(enabled=true)} 만으로는 부족했다. 스위치는 켜졌는데 자격증명을 읽지 못하는 상태에 해당하는 Bean 이
 * 하나도 없어, {@code FirebaseApp} 초기화 예외가 그대로 컨텍스트를 무너뜨리고 서비스 전면 중단으로 이어졌다(S15P11B209-681).
 *
 * <p>조건은 Bean 생성 <em>전에</em> 평가되므로, "만들다 실패"를 "애초에 만들지 않음"으로 바꿀 수 있다. 이것이 {@code try-catch} 로 예외를 삼키는
 * 것과 다른 점이다 — 삼킨 예외는 반쯤 만들어진 Bean 을 남기지만, 조건은 애초에 다른 구현({@link NoopPushSender})이 서게 한다.
 */
public class FcmAvailableCondition implements Condition {

  static final String ENABLED_PROPERTY = "app.push.fcm.enabled";
  static final String CREDENTIALS_PATH_PROPERTY = "app.push.fcm.credentials-path";

  @Override
  public boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata) {
    return isEnabled(context) && credentialAvailability(context).usable();
  }

  /** 발송 스위치가 켜져 있는지. 값이 없으면 꺼진 것으로 본다(application.yml 기본값과 동일). */
  static boolean isEnabled(ConditionContext context) {
    return context.getEnvironment().getProperty(ENABLED_PROPERTY, Boolean.class, false);
  }

  /** 설정된 경로의 자격증명이 쓸 수 있는 상태인지. */
  static FcmCredentials.Availability credentialAvailability(ConditionContext context) {
    return FcmCredentials.inspect(
        context.getEnvironment().getProperty(CREDENTIALS_PATH_PROPERTY));
  }
}
