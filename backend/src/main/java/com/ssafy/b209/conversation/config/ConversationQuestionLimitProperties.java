package com.ssafy.b209.conversation.config;

import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 대화 한 세션이 아이에게 던질 수 있는 질문 수 상한을 활동 유형별로 Binding한다 (S15P11B209-976).
 *
 * <p>이 값은 대화 세션을 만들 때 {@code conversation_sessions.max_question_count} 에 그대로 박히고, 이후 질문 요청은 그 열을 보고
 * 거부된다({@code ConversationSession.canAskQuestion} → 409 {@code CONVERSATION_409_001}). 즉 여기서 정한 수는
 * "이 대화가 최대 몇 번 물을 수 있는가"다.
 *
 * <p><b>단위는 그림 한 장이다.</b> HTP는 주제(집·나무·사람)마다 그림 세션이 따로 열리고 대화도 따로 열리므로, HTP 1회 활동이 실제로 던지는 질문은 최대
 * {@code htpPerSubject × 3} 이 된다. 그래서 키 이름을 {@code htp-per-subject} 로 두었다 — {@code htp} 라고만 쓰면 활동
 * 전체 상한으로 읽힌다.
 *
 * <p><b>⚠️ 소급 적용되지 않는다.</b> 이 값을 바꿔도 이미 만들어진 대화 세션의 {@code max_question_count} 는 그대로다. 세션 생성 시점에
 * 복사되는 Snapshot이기 때문이다(973 보관 기간과 같은 성질).
 *
 * @param htpPerSubject HTP 주제 하나(그림 한 장)당 질문 상한
 * @param artDiary 그림일기 한 장당 질문 상한
 */
@ConfigurationProperties(prefix = "app.conversation.question-limit")
public record ConversationQuestionLimitProperties(int htpPerSubject, int artDiary) {

  /**
   * 설정으로도 넘을 수 없는 절대 상한이다.
   *
   * <p>공개 요청 DTO({@code StartConversationRequest.maxQuestionCount})의 {@code @Max} 와 같은 값이어야 한다. 요청
   * 검증은 클라이언트가 보낸 값만 막으므로, 설정에 20을 적으면 아무 검증도 거치지 않고 20문짜리 세션이 만들어진다. 여기서 같은 선을 다시 긋는다.
   */
  public static final int ABSOLUTE_MAX = 10;

  /**
   * 활동 유형별 상한이 사용 가능한 범위 안에 있는지 검증한다.
   *
   * @param htpPerSubject HTP 주제당 질문 상한
   * @param artDiary 그림일기 질문 상한
   * @throws IllegalArgumentException 상한이 1 미만이거나 {@link #ABSOLUTE_MAX} 를 넘는 경우
   */
  public ConversationQuestionLimitProperties {
    validate("app.conversation.question-limit.htp-per-subject", htpPerSubject);
    validate("app.conversation.question-limit.art-diary", artDiary);
  }

  private static void validate(String key, int value) {
    if (value < 1) {
      // 0이면 세션이 만들어지자마자 첫 질문이 409로 막힌다 — 아이 화면에서 대화가 열리지 않는다.
      throw new IllegalArgumentException(key + " must be at least 1 but was " + value);
    }
    if (value > ABSOLUTE_MAX) {
      throw new IllegalArgumentException(
          key + " must not exceed " + ABSOLUTE_MAX + " but was " + value);
    }
  }

  /**
   * 활동 유형에 해당하는 질문 상한을 돌려준다.
   *
   * @param activityType 서버가 저장된 세션 관계에서 확정한 활동 유형
   * @return HTP면 주제당 상한, 그 밖(그림일기·유형 확정 실패)이면 그림일기 상한
   */
  public int limitFor(DrawingAnalysisActivityType activityType) {
    return activityType == DrawingAnalysisActivityType.HTP ? htpPerSubject : artDiary;
  }
}
