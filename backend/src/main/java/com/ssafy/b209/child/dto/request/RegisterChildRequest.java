package com.ssafy.b209.child.dto.request;

import com.ssafy.b209.child.domain.GuardianRelationshipType;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.domain.ResponseMode;
import io.swagger.v3.oas.annotations.media.ArraySchema;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Past;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.util.List;

/**
 * 보호자가 아동 프로필을 등록할 때 전달하는 입력값이다.
 *
 * <p>형식 제약만 이 요청에서 검증하고, 요청일 기준 만 나이 범위는 Service가 확인한다. {@code profileImageFileId}는 계약 호환을 위해 받지만
 * 현재 사전 업로드 이미지를 연결하는 기반이 없어 저장하지 않는다.
 *
 * @param nickname 아동 별칭
 * @param birthDate 아동 생년월일
 * @param relationshipType 보호자와 아동의 관계 유형
 * @param preferredCharacter 선호 캐릭터, 없으면 {@code null}
 * @param questionDifficulty 대화 질문 난이도
 * @param responseModes 아동이 사용할 응답 방식 목록, 1개 이상
 * @param profileImageFileId 사전 업로드 프로필 이미지 식별자, 없으면 {@code null}
 */
public record RegisterChildRequest(
    @Schema(description = "아동 별칭", example = "별이") @NotBlank @Size(max = 50) String nickname,
    @Schema(description = "아동 생년월일", example = "2018-05-10") @NotNull @Past LocalDate birthDate,
    @Schema(description = "보호자와 아동의 관계 유형", example = "MOTHER") @NotNull
        GuardianRelationshipType relationshipType,
    @Schema(description = "선호 캐릭터", example = "MONGLE") @Size(max = 50) String preferredCharacter,
    @Schema(description = "대화 질문 난이도", example = "LOWER_ELEMENTARY") @NotNull
        QuestionDifficulty questionDifficulty,
    @ArraySchema(schema = @Schema(implementation = ResponseMode.class, example = "EMOJI")) @NotEmpty
        List<@NotNull ResponseMode> responseModes,
    @Schema(description = "사전 업로드 프로필 이미지 식별자") @Size(max = 255) String profileImageFileId) {}
