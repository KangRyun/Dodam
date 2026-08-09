package com.ssafy.b209.infrastructure.push;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.notification.push.PushSender;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.boot.context.annotation.UserConfigurations;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;

/**
 * 푸시 발송 Bean 배선이 어떤 설정 조합에서도 컨텍스트를 무너뜨리지 않는지 확인한다.
 *
 * <p>핵심은 "스위치는 켜졌는데 자격증명을 쓸 수 없는" 조합이다. 이 조합에 해당하는 Bean 이 없어 컨텍스트가 붕괴했고, 그것이 서비스 전면 중단으로 이어졌다
 * (S15P11B209-681).
 */
class PushSenderWiringTest {

  @TempDir Path tempDir;

  private final ApplicationContextRunner runner =
      new ApplicationContextRunner()
          .withConfiguration(UserConfigurations.of(FcmConfig.class, PushTestBeans.class));

  @Test
  void 발송이_꺼져_있으면_noop_이_서고_기동한다() {
    runner
        .withPropertyValues("app.push.fcm.enabled=false")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context).hasSingleBean(PushSender.class);
              assertThat(context.getBean(PushSender.class)).isInstanceOf(NoopPushSender.class);
              assertThat(context.getBean(PushSender.class).isEnabled()).isFalse();
            });
  }

  @Test
  void 자격증명이_없어도_기동하고_noop_으로_떨어진다() {
    // 회귀 테스트: 예전에는 여기서 FirebaseApp 초기화 예외로 컨텍스트가 붕괴했다.
    runner
        .withPropertyValues(
            "app.push.fcm.enabled=true",
            "app.push.fcm.credentials-path=" + tempDir.resolve("없는파일.json"))
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context.getBean(PushSender.class)).isInstanceOf(NoopPushSender.class);
              assertThat(context).doesNotHaveBean(FcmPushSender.class);
            });
  }

  @Test
  void 자격증명을_읽지_못하면_health_가_degraded_로_드러난다() {
    // 조용히 꺼지면 "켰는데 왜 안 가지"를 아무도 모른다 — 반드시 관측 가능해야 한다.
    runner
        .withPropertyValues(
            "app.push.fcm.enabled=true",
            "app.push.fcm.credentials-path=" + tempDir.resolve("없는파일.json"))
        .run(
            context -> {
              PushHealthIndicator indicator = context.getBean(PushHealthIndicator.class);

              assertThat(indicator.isDegraded()).isTrue();
              assertThat(indicator.health().getDetails())
                  .containsEntry("configured", true)
                  .containsEntry("sending", false)
                  .containsEntry("degraded", true);
              assertThat(indicator.health().getStatus().getCode())
                  .as("푸시 문제로 전체 health 를 내리면 컨테이너 헬스체크가 실패해 배포가 막힌다")
                  .isEqualTo("UP");
            });
  }

  @Test
  void 발송이_꺼진_정상_구성에서는_degraded_가_아니다() throws IOException {
    Files.writeString(tempDir.resolve("sa.json"), "{}");

    runner
        .withPropertyValues(
            "app.push.fcm.enabled=false",
            "app.push.fcm.credentials-path=" + tempDir.resolve("sa.json"))
        .run(
            context -> {
              PushHealthIndicator indicator = context.getBean(PushHealthIndicator.class);

              assertThat(indicator.isDegraded()).isFalse();
              assertThat(indicator.health().getDetails()).containsEntry("degraded", false);
            });
  }

  @Configuration(proxyBeanMethods = false)
  @Import({FcmPushSender.class, NoopPushSender.class, PushHealthIndicator.class})
  static class PushTestBeans {

    @Bean
    MeterRegistry meterRegistry() {
      return new SimpleMeterRegistry();
    }
  }
}
