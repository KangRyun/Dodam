package com.ssafy.b209.child.dto.request;

import com.ssafy.b209.child.domain.GuardianRelationshipType;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.domain.ResponseMode;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Past;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.util.List;

/**
 * 연결 보호자가 아동 프로필에서 변경할 값을 전달한다.
 *
 * <p>전달하지 않은 필드는 유지한다. {@code profileImageFileId}는 현재 사전 업로드 이미지를 연결하는 기반이 없어 계약 호환 목적으로만 받는다.
 *
 * @param nickname 변경할 아동 별칭
 * @param birthDate 변경할 생년월일
 * @param relationshipType 요청 보호자와 아동의 변경할 관계 유형
 * @param preferredCharacter 변경할 선호 캐릭터
 * @param questionDifficulty 변경할 대화 질문 난이도
 * @param responseModes 변경할 응답 방식 목록
 * @param profileImageFileId 사전 업로드 프로필 이미지 식별자
 */
public record UpdateChildRequest(
    @Size(max = 50) @Pattern(regexp = ".*\\S.*") String nickname,
    @Past LocalDate birthDate,
    GuardianRelationshipType relationshipType,
    @Size(max = 50) String preferredCharacter,
    QuestionDifficulty questionDifficulty,
    @Size(min = 1) List<@NotNull ResponseMode> responseModes,
    @Size(max = 255) String profileImageFileId) {}
