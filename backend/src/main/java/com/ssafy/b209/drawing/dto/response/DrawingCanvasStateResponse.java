package com.ssafy.b209.drawing.dto.response;

import java.time.Instant;

/**
 * 최신 초안과 그림 이벤트 저장 지점을 맞추기 위한 최소 복구 기준이다.
 *
 * <p>도구 상태와 Viewport 복구는 별도 활동 재개 범위이며, 이 응답은 서버에 영속된 이벤트 순서와 클라이언트 저장 시각만 제공한다.
 *
 * @param lastEventSequence 초안 미리보기에 반영된 마지막 그림 이벤트 순서
 * @param clientSavedAt 클라이언트가 초안을 저장한 시각
 */
public record DrawingCanvasStateResponse(long lastEventSequence, Instant clientSavedAt) {}
