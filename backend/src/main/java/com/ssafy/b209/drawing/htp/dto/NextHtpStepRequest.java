package com.ssafy.b209.drawing.htp.dto;

import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;

/**
 * 다음 HTP 주제에서 사용할 입력 방식을 확정하는 요청이다.
 *
 * @param inputMethod 다음 HTP 단계의 Canvas 또는 이미지 업로드 방식
 */
public record NextHtpStepRequest(
    @Schema(description = "다음 HTP 주제의 입력 방식", example = "CANVAS") @NotNull
        DrawingInputMethod inputMethod) {}
