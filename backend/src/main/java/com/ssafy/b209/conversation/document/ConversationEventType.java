package com.ssafy.b209.conversation.document;

/**
 * MongoDB {@code conversation_events} 에 적재하는 대화 행동의 종류다 (S15P11B209-973).
 *
 * <p><b>여기 있는 값은 전부 실제 적재 경로가 있다.</b> "언젠가 쓸지도 모르는" 값을 미리 넣지 않는다 — 아무도 쓰지 않는 enum 값은 소비자(리포트·분석)에게
 * "이 이벤트가 오는데 지금은 0건이구나"라는 잘못된 신호를 준다. 실제로 이 저장소에는 호출되지 않는 저장 메서드가 몇 주간 방치돼 화면이 빈 채로 나간 전례가 있다
 * (S15P11B209-902). 새 종류를 추가할 때는 적재 훅을 같은 커밋에 함께 넣을 것.
 *
 * <p><b>질문 미응답(timeout)이 없는 이유</b>: 서버는 "아이가 답을 안 했다"를 관측할 수단이 없다. 응답 없음은 요청이 오지 않는 상태라 훅을 걸 지점 자체가
 * 없기 때문이다. 녹음이 시간 초과로 끝난 경우는 {@link #ANSWER_VOICE} 의 {@code stopReason=TIMEOUT} 으로 남는다. 질문 단위의 무응답을
 * 알고 싶다면 {@link #QUESTION_SHOWN} 이 있는데 뒤따르는 답변·건너뛰기 이벤트가 없는 질문을 소비자가 계산하면 된다.
 */
public enum ConversationEventType {

  /** AI 질문이 저장돼 아이 화면으로 내려갔다. 이 질문에 대한 응답 지연 계산의 기준점이다. */
  QUESTION_SHOWN,

  /** 아이가 마이크로 답했다(음성 파일 저장 완료 시점). */
  ANSWER_VOICE,

  /** 아이가 선택 칩으로 답했다. */
  ANSWER_CHIP,

  /** 아이가 질문에 답하지 않고 넘어갔다. */
  SKIP,

  /** 대화가 종료됐다. */
  SESSION_END
}
