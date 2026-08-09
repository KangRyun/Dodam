package com.ssafy.b209.conversation.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 대화 행동 이벤트의 보관 기간을 외부 환경에서 Binding한다 (S15P11B209-973).
 *
 * <p>이 값으로 계산한 {@code expireAt} 을 문서마다 들고 가고, MongoDB TTL 인덱스({@code expireAfterSeconds: 0})가 그 시각을
 * 보고 지운다. 기간을 인덱스에 박지 않는 이유는 보관 정책이 데이터 종류마다 다르고 동의 철회 시 앞당겨야 할 수도 있기 때문이다(스트로크와 같은 규칙 — {@code
 * StrokeRetentionProperties}).
 *
 * <p><b>⚠️ 소급 적용되지 않는다.</b> 이 값을 바꿔도 이미 저장된 문서의 {@code expireAt} 은 그대로다. TTL 인덱스는 문서에 적힌 시각만 본다.
 *
 * @param retentionDays 보관 기간(일). 1 이상이어야 한다
 */
@ConfigurationProperties(prefix = "app.conversation-event")
public record ConversationEventRetentionProperties(int retentionDays) {

  /**
   * 보관 기간이 아동 데이터를 즉시 만료시키지 않도록 불변 조건을 검증한다.
   *
   * @param retentionDays 보관 기간(일)
   * @throws IllegalArgumentException 보관 기간이 1일 미만인 경우
   */
  public ConversationEventRetentionProperties {
    if (retentionDays < 1) {
      // 0 이나 음수를 허용하면 적재하는 순간 만료된 문서가 되어, 방금 일어난 대화가 60초 안에 사라진다.
      throw new IllegalArgumentException("Conversation event retention days must be at least 1");
    }
  }

  /**
   * 보관 기간을 시각 계산에 쓰는 {@link Duration} 으로 환산한다.
   *
   * @return 보관 기간
   */
  public Duration retention() {
    return Duration.ofDays(retentionDays);
  }
}
