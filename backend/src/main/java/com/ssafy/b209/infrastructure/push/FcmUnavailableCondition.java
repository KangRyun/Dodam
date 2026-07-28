package com.ssafy.b209.infrastructure.push;

import org.springframework.context.annotation.Condition;
import org.springframework.context.annotation.ConditionContext;
import org.springframework.core.type.AnnotatedTypeMetadata;

/**
 * {@link FcmAvailableCondition} 의 부정 — 발송을 할 수 없는 모든 경우다.
 *
 * <p>스위치가 꺼진 경우와 "켜려 했으나 자격증명을 쓸 수 없는" 경우를 함께 덮는다. 두 조건이 서로의 여집합이라 {@link PushSender} 구현이 항상 정확히 하나
 * 존재한다 — {@code @ConditionalOnMissingBean} 대신 명시적 부정을 쓰는 이유다. {@code @ConditionalOnMissingBean} 은
 * 일반 {@code @Component} 에서 평가 순서에 의존해 결과가 흔들릴 수 있다.
 */
public class FcmUnavailableCondition implements Condition {

  private final FcmAvailableCondition available = new FcmAvailableCondition();

  @Override
  public boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata) {
    return !available.matches(context, metadata);
  }
}
