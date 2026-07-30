package com.ssafy.b209.child.dto.response;

import com.ssafy.b209.child.domain.ChildTutorialStatus;
import java.time.Instant;

/**
 * 보호자가 조회할 수 있는 아동 Tutorial 진행 상태를 나타낸다.
 *
 * <p>{@code lastStep}은 진행 중인 안내 화면을 복원하는 식별자이며, 완료하거나 건너뛴 시각은 {@code completedAt}으로 제공한다. 아직 진행 단계나
 * 종료 시각이 정해지지 않은 경우 해당 값은 {@code null}이다.
 *
 * @param childId 아동 식별자
 * @param tutorialStatus 현재 Tutorial 상태
 * @param lastStep 마지막으로 저장된 Tutorial 단계 식별자
 * @param completedAt Tutorial 완료 또는 건너뛰기 시각
 * @param updatedAt Tutorial 진행 정보가 마지막으로 변경된 시각
 */
public record ChildTutorialProgressResponse(
    Long childId,
    ChildTutorialStatus tutorialStatus,
    String lastStep,
    Instant completedAt,
    Instant updatedAt) {}
