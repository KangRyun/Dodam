package com.ssafy.b209.child.dto.response;

import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import java.time.LocalDate;

/**
 * 연결 보호자에게 노출할 아동 목록 항목이다.
 *
 * <p>목록 화면에서 아동을 식별하고 선택하는 데 필요한 요약 정보만 포함하며 조회 시점의 만 나이를 함께 제공한다. 상세 정보는 아동 상세 조회 API에서 제공한다.
 *
 * @param childId 아동 식별자
 * @param nickname 아동 별칭
 * @param birthDate 아동 생년월일
 * @param age 조회일 기준 만 나이
 * @param profileImageUrl 프로필 이미지 URL, 등록되지 않았으면 {@code null}
 * @param questionDifficulty 대화 질문 난이도
 * @param tutorialStatus Tutorial 진행 상태
 * @param profileStatus 프로필 상태
 * @param relationshipType 조회 보호자와 아동의 관계 유형
 */
public record ChildSummaryResponse(
    Long childId,
    String nickname,
    LocalDate birthDate,
    int age,
    String profileImageUrl,
    QuestionDifficulty questionDifficulty,
    ChildTutorialStatus tutorialStatus,
    ChildProfileStatus profileStatus,
    String relationshipType) {}
