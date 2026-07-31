package com.ssafy.b209.child.dto.response;

import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.GuardianRelationshipType;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.domain.ResponseMode;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/**
 * 등록된 아동 프로필과 등록 보호자와의 관계를 반환한다.
 *
 * <p>등록 시점의 만 나이와 초기 상태를 포함하며 응답 방식은 저장된 순서를 유지한다.
 *
 * @param childId 아동 식별자
 * @param nickname 아동 별칭
 * @param birthDate 아동 생년월일
 * @param age 등록일 기준 만 나이
 * @param relationshipType 등록 보호자와 아동의 관계 유형
 * @param preferredCharacter 선호 캐릭터, 등록되지 않았으면 {@code null}
 * @param questionDifficulty 대화 질문 난이도
 * @param responseModes 아동이 사용할 수 있는 응답 방식 목록
 * @param tutorialStatus 초기 Tutorial 진행 상태
 * @param profileStatus 프로필 상태
 * @param profileImageUrl 인증 후 조회할 수 있는 프로필 이미지 URL, 이미지가 없으면 {@code null}
 * @param createdAt 프로필 생성 시각
 */
public record ChildRegistrationResponse(
    Long childId,
    String nickname,
    LocalDate birthDate,
    int age,
    GuardianRelationshipType relationshipType,
    String preferredCharacter,
    QuestionDifficulty questionDifficulty,
    List<ResponseMode> responseModes,
    ChildTutorialStatus tutorialStatus,
    ChildProfileStatus profileStatus,
    String profileImageUrl,
    Instant createdAt) {

  /** 응답 방식 목록을 외부에서 변경할 수 없도록 복사한다. */
  public ChildRegistrationResponse {
    responseModes = List.copyOf(responseModes);
  }
}
