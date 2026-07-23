package com.ssafy.b209.consent.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.consent.domain.ConsentTargetScope;
import com.ssafy.b209.consent.domain.ConsentTerm;
import com.ssafy.b209.consent.dto.response.ConsentTermResponse;
import com.ssafy.b209.consent.repository.ConsentTermRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class ConsentTermQueryServiceTest {

  private static final Clock CLOCK =
      Clock.fixed(Instant.parse("2026-07-23T12:00:00Z"), ZoneOffset.UTC);
  private static final LocalDateTime PAST = LocalDateTime.of(2020, 1, 1, 0, 0);
  private static final LocalDateTime FUTURE = LocalDateTime.of(2999, 1, 1, 0, 0);

  @Mock private ConsentTermRepository consentTermRepository;

  private ConsentTermQueryService service;

  @BeforeEach
  void setUp() {
    service = new ConsentTermQueryService(consentTermRepository, CLOCK);
  }

  @Test
  void returnsEffectiveActiveTermsFilteredByScope() {
    given(consentTermRepository.findAllByActiveTrue())
        .willReturn(
            List.of(
                term(1L, "SERVICE_TOS", ConsentTargetScope.USER, true, "v1", PAST, true),
                term(2L, "CHILD_DATA", ConsentTargetScope.CHILD, true, "v1", PAST, true),
                term(3L, "FUTURE_TERM", ConsentTargetScope.USER, false, "v2", FUTURE, true)));

    List<ConsentTermResponse> terms = service.getActiveTerms(ConsentTargetScope.USER, null);

    assertThat(terms).hasSize(1);
    assertThat(terms.getFirst().termCode()).isEqualTo("SERVICE_TOS");
    assertThat(terms.getFirst().targetScope()).isEqualTo(ConsentTargetScope.USER);
    assertThat(terms.getFirst().required()).isTrue();
    assertThat(terms.getFirst().effectiveAt()).isEqualTo(PAST.toInstant(ZoneOffset.UTC));
  }

  @Test
  void returnsAllEffectiveActiveTermsWhenNoFilterIsGiven() {
    given(consentTermRepository.findAllByActiveTrue())
        .willReturn(
            List.of(
                term(1L, "SERVICE_TOS", ConsentTargetScope.USER, true, "v1", PAST, true),
                term(2L, "CHILD_DATA", ConsentTargetScope.CHILD, true, "v1", PAST, true),
                term(3L, "FUTURE_TERM", ConsentTargetScope.USER, false, "v2", FUTURE, true)));

    List<ConsentTermResponse> terms = service.getActiveTerms(null, null);

    assertThat(terms)
        .extracting(ConsentTermResponse::termCode)
        .containsExactly("SERVICE_TOS", "CHILD_DATA");
  }

  private ConsentTerm term(
      Long id,
      String code,
      ConsentTargetScope scope,
      boolean required,
      String version,
      LocalDateTime effectiveAt,
      boolean active) {
    ConsentTerm term =
        ConsentTerm.define(
            code,
            scope,
            required,
            version,
            code + " 제목",
            "https://example.com/" + code,
            effectiveAt,
            active,
            PAST);
    ReflectionTestUtils.setField(term, "id", id);
    return term;
  }
}
