package com.ssafy.b209.child.dto.response;

import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/**
 * 연결 보호자에게 공개할 아동 상세 프로필이다.
 *
 * <p>아동 기본 정보와 현재 보호자와의 관계, 선택 가능한 응답 방식을 함께 제공한다. DB Entity를 직접 노출하지 않으며 조회 시점의 만 나이를 포함한다.
 *
 * @param childId 아동 식별자
 * @param nickname 아동 별칭
 * @param birthDate 아동 생년월일
 * @param age 조회일 기준 만 나이
 * @param profileImageUrl 프로필 이미지 URL, 등록되지 않았으면 {@code null}
 * @param preferredCharacter 선호 캐릭터, 등록되지 않았으면 {@code null}
 * @param questionDifficulty 대화 질문 난이도
 * @param educationStage 아이가 다니는 곳({@code PRESCHOOL}·{@code KINDERGARTEN}·{@code GRADE_1}). 고르지
 *     않았으면 {@code UNKNOWN} 이다 — 저장은 {@code NULL} 이고 응답에서만 이 값으로 바꾼다
 *     (S15P11B209-1010 v2)
 * @param responseModes 아동이 사용할 수 있는 응답 방식 목록
 * @param tutorialStatus Tutorial 진행 상태
 * @param profileStatus 프로필 상태
 * @param relationshipType 조회 보호자와 아동의 관계 유형
 * @param createdAt 프로필 생성 시각
 * @param updatedAt 프로필 마지막 수정 시각
 */
public record ChildDetailResponse(
    Long childId,
    String nickname,
    LocalDate birthDate,
    int age,
    String profileImageUrl,
    String preferredCharacter,
    QuestionDifficulty questionDifficulty,
    String educationStage,
    List<String> responseModes,
    ChildTutorialStatus tutorialStatus,
    ChildProfileStatus profileStatus,
    String relationshipType,
    Instant createdAt,
    Instant updatedAt) {

  /** 응답 방식 목록을 외부에서 변경할 수 없도록 복사한다. */
  public ChildDetailResponse {
    responseModes = List.copyOf(responseModes);
  }
}
