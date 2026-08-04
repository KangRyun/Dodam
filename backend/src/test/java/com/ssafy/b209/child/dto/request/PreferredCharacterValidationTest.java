package com.ssafy.b209.child.dto.request;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.child.domain.GuardianRelationshipType;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.domain.ResponseMode;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.time.LocalDate;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullSource;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * 선호 캐릭터 코드 허용 목록 계약(S15P11B209-866).
 *
 * <p>Flutter의 {@code DodamCostume}·{@code supportedPreferredCharacters}와 DB CHECK 제약이 같은 7종을 가리켜야
 * 한다. 한쪽만 넓히면 아동이 고른 캐릭터가 400으로 거부되거나 조용히 사라진다.
 */
class PreferredCharacterValidationTest {

  private static final String PROPERTY = "preferredCharacter";

  private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

  private RegisterChildRequest registerWith(String preferredCharacter) {
    return new RegisterChildRequest(
        "별이",
        LocalDate.of(2019, 3, 15),
        GuardianRelationshipType.MOTHER,
        preferredCharacter,
        QuestionDifficulty.LOWER_ELEMENTARY,
        List.of(ResponseMode.VOICE),
        null);
  }

  private UpdateChildRequest updateWith(String preferredCharacter) {
    return new UpdateChildRequest(null, null, null, preferredCharacter, null, null, null);
  }

  private boolean violatesPreferredCharacter(Set<? extends ConstraintViolation<?>> violations) {
    return violations.stream()
        .anyMatch(violation -> violation.getPropertyPath().toString().equals(PROPERTY));
  }

  @ParameterizedTest
  @ValueSource(strings = {"BASE", "PRINCESS", "DINO", "OCTOPUS", "EXPLORER", "RIBBON", "PRINCE"})
  void acceptsEveryCharacterCodeOnRegistration(String code) {
    assertThat(violatesPreferredCharacter(validator.validate(registerWith(code)))).isFalse();
  }

  @ParameterizedTest
  @ValueSource(strings = {"BASE", "PRINCESS", "DINO", "OCTOPUS", "EXPLORER", "RIBBON", "PRINCE"})
  void acceptsEveryCharacterCodeOnUpdate(String code) {
    assertThat(violatesPreferredCharacter(validator.validate(updateWith(code)))).isFalse();
  }

  @ParameterizedTest
  @ValueSource(strings = {"EXPLORER", "RIBBON", "PRINCE"})
  void acceptsTheThreeNewCharactersAddedByThisIssue(String code) {
    assertThat(violatesPreferredCharacter(validator.validate(registerWith(code)))).isFalse();
    assertThat(violatesPreferredCharacter(validator.validate(updateWith(code)))).isFalse();
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "MONGLE",
        "BOY",
        "GIRL",
        "KING",
        "UNKNOWN",
        "base",
        "explorer",
        "PRINCE ",
        " PRINCE",
        "PRINCESS|DINO",
        "",
        " ",
        "   "
      })
  void rejectsCodesOutsideTheAllowedListOnRegistration(String code) {
    assertThat(violatesPreferredCharacter(validator.validate(registerWith(code)))).isTrue();
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "MONGLE",
        "BOY",
        "GIRL",
        "KING",
        "UNKNOWN",
        "base",
        "explorer",
        "PRINCE ",
        " PRINCE",
        "",
        " "
      })
  void rejectsCodesOutsideTheAllowedListOnUpdate(String code) {
    assertThat(violatesPreferredCharacter(validator.validate(updateWith(code)))).isTrue();
  }

  /** 등록·수정 모두 캐릭터를 고르지 않는 흐름을 유지한다(V28 이후 DB도 NULL 허용). */
  @ParameterizedTest
  @NullSource
  void keepsPreferredCharacterOptional(String code) {
    assertThat(violatesPreferredCharacter(validator.validate(registerWith(code)))).isFalse();
    assertThat(violatesPreferredCharacter(validator.validate(updateWith(code)))).isFalse();
  }

  /** 명시적 null은 선택 해제이므로 "전달했다"는 사실 자체는 보존되어야 한다. */
  @Test
  void treatsExplicitNullOnUpdateAsAnUnsetRequest() {
    UpdateChildRequest request = new UpdateChildRequest();
    request.setPreferredCharacter(null);

    assertThat(request.preferredCharacterSpecified()).isTrue();
    assertThat(request.preferredCharacter()).isNull();
    assertThat(violatesPreferredCharacter(validator.validate(request))).isFalse();
  }
}
