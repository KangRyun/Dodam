package com.ssafy.b209.global.support;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class ColumnTextLimiterTest {

  private static final String COLUMN = "sample_table.sample_column";

  @Test
  void keepsValueWithinLimit() {
    assertThat(ColumnTextLimiter.fit("가나다", 10, COLUMN)).isEqualTo("가나다");
  }

  @Test
  void keepsValueExactlyAtLimit() {
    assertThat(ColumnTextLimiter.fit("가나다", 3, COLUMN)).isEqualTo("가나다");
  }

  @Test
  void keepsNull() {
    assertThat(ColumnTextLimiter.fit(null, 10, COLUMN)).isNull();
  }

  @Test
  void truncatesValueOverLimit() {
    assertThat(ColumnTextLimiter.fit("가나다라마", 3, COLUMN)).isEqualTo("가나다");
  }

  @Test
  void countsKoreanCharactersOneByOne() {
    // MySQL VARCHAR(n)은 Byte가 아니라 문자 수를 센다. 한글 30자는 utf8mb4에서 90Byte지만 30자다.
    String value = "가".repeat(30);

    assertThat(ColumnTextLimiter.fit(value, 30, COLUMN)).isEqualTo(value);
  }

  @Test
  void countsSupplementaryCharacterAsOneCharacter() {
    // Emoji 3자는 String.length()로 6이지만 MySQL이 세는 문자 수는 3이라 자르면 안 된다.
    String value = "😀😀😀";
    assertThat(value.length()).isEqualTo(6);

    assertThat(ColumnTextLimiter.fit(value, 3, COLUMN)).isEqualTo(value);
  }

  @Test
  void truncatesSupplementaryCharacterOnCodePointBoundary() {
    String result = ColumnTextLimiter.fit("😀😀😀", 2, COLUMN);

    assertThat(result).isEqualTo("😀😀");
    assertThat(result.codePointCount(0, result.length())).isEqualTo(2);
    // 끝에 High Surrogate만 남으면 Pair가 쪼개진 것이라 저장할 수 없는 문자열이 된다.
    assertThat(Character.isHighSurrogate(result.charAt(result.length() - 1))).isFalse();
  }

  @Test
  void truncatesMixedKoreanAndSupplementaryCharacters() {
    String result = ColumnTextLimiter.fit("가😀나", 2, COLUMN);

    assertThat(result).isEqualTo("가😀");
    assertThat(result.codePointCount(0, result.length())).isEqualTo(2);
  }

  @Test
  void rejectsNonPositiveLimit() {
    assertThatThrownBy(() -> ColumnTextLimiter.fit("가나다", 0, COLUMN))
        .isInstanceOf(IllegalArgumentException.class);
  }
}
