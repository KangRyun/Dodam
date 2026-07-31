package com.ssafy.b209.child.dto.request;

import com.fasterxml.jackson.annotation.JsonAutoDetect;
import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonSetter;
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
 * <p>전달하지 않은 필드는 유지한다. {@code profileImageFileId}와 {@code preferredCharacter}는 명시적 {@code null}을
 * 전달하면 각각 기존 이미지와 캐릭터 선택을 삭제한다.
 */
@JsonAutoDetect(fieldVisibility = JsonAutoDetect.Visibility.ANY)
public class UpdateChildRequest {

  @Size(max = 50)
  @Pattern(regexp = ".*\\S.*")
  private String nickname;

  @Past private LocalDate birthDate;
  private GuardianRelationshipType relationshipType;

  @Pattern(regexp = "BASE|PRINCESS|DINO|OCTOPUS")
  private String preferredCharacter;

  private QuestionDifficulty questionDifficulty;

  @Size(min = 1)
  private List<@NotNull ResponseMode> responseModes;

  @Size(max = 255)
  private String profileImageFileId;

  @JsonIgnore private boolean profileImageFileIdSpecified;
  @JsonIgnore private boolean preferredCharacterSpecified;

  public UpdateChildRequest() {}

  public UpdateChildRequest(
      String nickname,
      LocalDate birthDate,
      GuardianRelationshipType relationshipType,
      String preferredCharacter,
      QuestionDifficulty questionDifficulty,
      List<ResponseMode> responseModes,
      String profileImageFileId) {
    this.nickname = nickname;
    this.birthDate = birthDate;
    this.relationshipType = relationshipType;
    this.preferredCharacter = preferredCharacter;
    this.preferredCharacterSpecified = preferredCharacter != null;
    this.questionDifficulty = questionDifficulty;
    this.responseModes = responseModes;
    this.profileImageFileId = profileImageFileId;
    this.profileImageFileIdSpecified = profileImageFileId != null;
  }

  public String nickname() {
    return nickname;
  }

  public LocalDate birthDate() {
    return birthDate;
  }

  public GuardianRelationshipType relationshipType() {
    return relationshipType;
  }

  public String preferredCharacter() {
    return preferredCharacter;
  }

  public boolean preferredCharacterSpecified() {
    return preferredCharacterSpecified;
  }

  public QuestionDifficulty questionDifficulty() {
    return questionDifficulty;
  }

  public List<ResponseMode> responseModes() {
    return responseModes;
  }

  public String profileImageFileId() {
    return profileImageFileId;
  }

  public boolean profileImageFileIdSpecified() {
    return profileImageFileIdSpecified;
  }

  @JsonSetter("profileImageFileId")
  public void setProfileImageFileId(String profileImageFileId) {
    this.profileImageFileId = profileImageFileId;
    this.profileImageFileIdSpecified = true;
  }

  @JsonSetter("preferredCharacter")
  public void setPreferredCharacter(String preferredCharacter) {
    this.preferredCharacter = preferredCharacter;
    this.preferredCharacterSpecified = true;
  }
}
