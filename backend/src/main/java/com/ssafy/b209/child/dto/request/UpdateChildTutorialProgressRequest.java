package com.ssafy.b209.child.dto.request;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 아동 Tutorial의 상태와 마지막 진행 단계를 변경하는 요청이다.
 *
 * <p>{@code tutorialStatus}는 필수이며 {@code lastStep}은 화면 복원이 필요한 경우에만 전달한다. 이전 명세의 {@code status}
 * 필드명도 입력 호환을 위해 허용하지만 응답과 신규 클라이언트는 {@code tutorialStatus}를 사용한다.
 *
 * @param tutorialStatus 변경할 Tutorial 상태
 * @param lastStep 마지막으로 완료하거나 표시한 Tutorial 단계 식별자
 */
public record UpdateChildTutorialProgressRequest(
    @NotNull @JsonAlias("status") ChildTutorialStatus tutorialStatus,
    @Size(max = 50) String lastStep) {}
