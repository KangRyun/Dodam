package com.ssafy.b209.drawing.service;

import com.ssafy.b209.drawing.dto.response.StrokeBatchResponse;

/**
 * Stroke 배치 저장 결과와 신규 생성 여부를 Controller에 전달한다.
 *
 * @param response 공개 저장 결과
 * @param created 새 배치를 만들었으면 {@code true}, 같은 payload 재전송이면 {@code false}
 */
public record StrokeBatchSaveResult(StrokeBatchResponse response, boolean created) {}
