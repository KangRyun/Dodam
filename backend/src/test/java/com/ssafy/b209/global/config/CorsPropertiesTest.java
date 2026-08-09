package com.ssafy.b209.global.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class CorsPropertiesTest {

  @Test
  void normalizesOriginsWithoutRetainingTheMutableSource() {
    var source =
        new ArrayList<>(
            List.of(
                " http://localhost:3000 ", "", "http://localhost:3000", "http://127.0.0.1:3000"));

    var properties = new CorsProperties(source);
    source.clear();

    assertThat(properties.allowedOrigins())
        .containsExactly("http://localhost:3000", "http://127.0.0.1:3000");
    assertThatThrownBy(() -> properties.allowedOrigins().add("https://example.com"))
        .isInstanceOf(UnsupportedOperationException.class);
  }

  @Test
  void usesAnEmptyListWhenOriginsAreNotConfigured() {
    assertThat(new CorsProperties(null).allowedOrigins()).isEmpty();
  }

  @ParameterizedTest
  @ValueSource(strings = {"http://localhost", "http://localhost:0", "https://localhost:65535"})
  void acceptsOriginsWithAbsentOrBoundaryPorts(String origin) {
    assertThat(new CorsProperties(List.of(origin)).allowedOrigins()).containsExactly(origin);
  }

  @ParameterizedTest
  @ValueSource(strings = {"http://localhost:", "http://localhost:65536", "http://localhost:99999"})
  void rejectsOriginsWithEmptyOrOutOfRangePorts(String origin) {
    assertThatIllegalArgumentException()
        .isThrownBy(() -> new CorsProperties(List.of(origin)))
        .withMessage("Invalid CORS origin")
        .withNoCause();
  }

  @Test
  void doesNotExposeMalformedOriginInTheValidationException() {
    String malformedOrigin = "http://[::1";

    assertThatIllegalArgumentException()
        .isThrownBy(() -> new CorsProperties(List.of(malformedOrigin)))
        .withMessage("Invalid CORS origin")
        .withNoCause();
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "*",
        "http://localhost:3000/",
        "http://localhost:3000/api",
        "localhost:3000",
        "ftp://localhost:3000",
        "http://user@localhost:3000",
        "http://localhost:3000?mode=test",
        "http://localhost:3000#fragment"
      })
  void rejectsValuesThatAreNotOrigins(String origin) {
    assertThatIllegalArgumentException().isThrownBy(() -> new CorsProperties(List.of(origin)));
  }
}
