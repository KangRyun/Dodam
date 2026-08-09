package com.ssafy.b209.conversation.dto;

import java.time.Instant;
import java.util.List;

/**
 * 외부 앱에 반환하는 저장 완료 AI 질문 메시지다.
 *
 * <p>{@code confirmedStopTarget}은 아이가 되묻기에 <strong>말로</strong> 그만하겠다고 확인했을 때만 실린다
 * (S15P11B209-951). 명령이 아니라 관찰 보고이며, 실제 종료는 앱이 기존 종료 흐름으로 수행한다 — 대화 종료는 되돌리기 쉽고 활동 완료는
 * 회고 저장·다음 단계로 이어져 되돌릴 수 없다. 값이 {@code null}이면 951 이전과 완전히 같게 동작한다.
 */
public record NextQuestionResponse(
    Long messageId,
    Long conversationId,
    int sequence,
    String senderType,
    String messageType,
    String text,
    List<NextQuestionOptionResponse> options,
    NextQuestionTargetResponse targetObject,
    boolean ttsAvailable,
    Instant createdAt,
    String confirmedStopTarget) {}
