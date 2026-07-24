package com.ssafy.b209.child.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import java.time.Instant;
import java.time.LocalDate;

/**
 * 연결 보호자에게 노출할 아동 목록 항목이다.
 *
 * <p>보호자 홈에서 아동을 식별하고 선택하는 데 필요한 요약 정보와 함께, 카드 UI에 표시할 최근 활동 요약을 제공한다. 조회 시점의 만 나이는 계산 필드이며 상세 정보는
 * 아동 상세 조회 API에서 제공한다.
 *
 * @param childId 아동 식별자
 * @param nickname 아동 별칭
 * @param birthDate 아동 생년월일
 * @param age 조회일 기준 만 나이
 * @param profileImageUrl 프로필 이미지 URL, 등록되지 않았으면 {@code null}
 * @param preferredCharacter 선호 캐릭터, 등록되지 않았으면 {@code null}
 * @param questionDifficulty 대화 질문 난이도
 * @param tutorialStatus Tutorial 진행 상태
 * @param profileStatus 프로필 상태
 * @param relationshipType 조회 보호자와 아동의 관계 유형
 * @param recentActivity 삭제되지 않은 그림 세션 기준 최근 활동 요약
 */
public record ChildSummaryResponse(
    Long childId,
    String nickname,
    LocalDate birthDate,
    int age,
    String profileImageUrl,
    String preferredCharacter,
    QuestionDifficulty questionDifficulty,
    ChildTutorialStatus tutorialStatus,
    ChildProfileStatus profileStatus,
    String relationshipType,
    RecentActivity recentActivity) {

  /**
   * 보호자 홈 카드에 표시할 아동의 최근 활동 요약이다.
   *
   * <p>삭제되지 않은 그림 세션만 집계하며 저장 값이 아니라 조회 시점에 계산한 값이다.
   *
   * @param lastActivityAt 마지막 그림 세션 시작 시각, 활동 이력이 없으면 {@code null}
   * @param totalActivityCount 삭제 제외 누적 그림 세션 수
   */
  public record RecentActivity(
      @JsonFormat(shape = JsonFormat.Shape.STRING) Instant lastActivityAt,
      long totalActivityCount) {}
}
