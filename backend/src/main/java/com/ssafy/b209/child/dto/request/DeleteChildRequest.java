package com.ssafy.b209.child.dto.request;

/**
 * 아동 프로필 삭제의 명시적 확인 값을 전달한다.
 *
 * <p>Bean Validation 제약을 두지 않는다. 본문 누락·공백·오값이 모두 같은 오류로 응답해야 하므로 확인 값 검증은 {@code
 * ChildDeletionService}가 단독으로 수행한다.
 *
 * @param confirmation 오작동 방지를 위해 정확히 {@code DELETE}여야 하는 확인 문자열
 */
public record DeleteChildRequest(String confirmation) {}
