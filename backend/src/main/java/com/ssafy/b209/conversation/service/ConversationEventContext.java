package com.ssafy.b209.conversation.service;

/**
 * 대화 행동 이벤트가 어느 대화·아동·활동의 것인지 가리키는 좌표다 (S15P11B209-973).
 *
 * <p>세 값을 개별 인자로 흘리면 훅이 늘어날 때마다 호출부 시그니처가 길어지고 인자 순서를 바꿔 넣는 실수가 난다(셋 다 {@code Long} 이라 컴파일러가 잡아주지
 * 못한다). 하나로 묶어 호출부에서 한 번만 조립한다.
 *
 * @param conversationSessionId 대화 세션 ID({@code conversation_sessions.id}). 문서의 {@code sessionId} 가
 *     된다
 * @param childId 아동 ID({@code children.id}). 스트로크와 같은 식별 체계이며 탈퇴·삭제 시 동반 삭제 키다
 * @param drawingSessionId 그림 활동 세션 ID({@code drawing_sessions.id}). {@code strokes} 의 {@code
 *     sessionId} 와 같은 값이다
 */
public record ConversationEventContext(
    Long conversationSessionId, Long childId, Long drawingSessionId) {}
