package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;

/**
 * 활동 기록에서 HTP 묶음에 포함된 그림 한 장을 반환한다.
 *
 * @param drawingSubject 집, 나무, 사람 그림 주제
 * @param drawingSessionId 그림 단계 세션 식별자
 * @param thumbnailUrl 인증이 필요한 그림 미리보기 상대 URL
 */
public record HtpDrawingHistoryResponse(
    HtpDrawingSubject drawingSubject, Long drawingSessionId, String thumbnailUrl) {}
