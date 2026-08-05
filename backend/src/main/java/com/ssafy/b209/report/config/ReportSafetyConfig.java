package com.ssafy.b209.report.config;

import com.ssafy.b209.report.safety.InterpretationSafetyVerifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 경향 해석 안전 검증기를 빈으로 등록한다 (S15P11B209-902).
 *
 * <p>{@code report.safety} 패키지는 Spring 을 모르는 순수 계산 코드다(S15P11B209-901). 그 결정을 유지하기 위해 클래스에
 * {@code @Component}를 붙이지 않고 여기서 조립한다 — 검증 규칙을 단위 테스트에서 프레임워크 없이 그대로 돌릴 수 있어야 한다.
 */
@Configuration
public class ReportSafetyConfig {

  /**
   * 구조적 공개 게이트와 표현 안전 필터를 묶은 검증기를 등록한다.
   *
   * @return 기본 규칙으로 구성한 검증기
   */
  @Bean
  public InterpretationSafetyVerifier interpretationSafetyVerifier() {
    return new InterpretationSafetyVerifier();
  }
}
