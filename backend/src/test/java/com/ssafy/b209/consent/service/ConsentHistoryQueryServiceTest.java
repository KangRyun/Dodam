package com.ssafy.b209.consent.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.consent.domain.ConsentAction;
import com.ssafy.b209.consent.domain.ConsentTargetScope;
import com.ssafy.b209.consent.exception.ConsentErrorCode;
import com.ssafy.b209.consent.repository.ConsentAuthorizationRepository;
import com.ssafy.b209.consent.repository.ConsentHistoryPage;
import com.ssafy.b209.consent.repository.ConsentHistoryRepository;
import com.ssafy.b209.consent.repository.ConsentHistoryRow;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ConsentHistoryQueryServiceTest {

  @Mock private ConsentHistoryRepository historyRepository;
  @Mock private ConsentAuthorizationRepository authorizationRepository;

  private ConsentHistoryQueryService service;

  @BeforeEach
  void setUp() {
    service = new ConsentHistoryQueryService(historyRepository, authorizationRepository);
  }

  @Test
  void mapsAccessibleVersionedHistoryAndPageMetadata() {
    LocalDate from = LocalDate.of(2026, 7, 1);
    LocalDate to = LocalDate.of(2026, 7, 24);
    when(authorizationRepository.hasGuardianChildRelation(41L, 7L)).thenReturn(true);
    when(historyRepository.findAccessibleHistory(
            41L,
            7L,
            "CHILD_PERSONAL_DATA",
            from.atStartOfDay(),
            to.plusDays(1).atStartOfDay(),
            0,
            20))
        .thenReturn(
            new ConsentHistoryPage(
                List.of(
                    new ConsentHistoryRow(
                        12L,
                        3L,
                        "CHILD_PERSONAL_DATA",
                        ConsentTargetScope.CHILD,
                        true,
                        "v2",
                        "아동 개인정보 동의",
                        7L,
                        ConsentAction.AGREE,
                        LocalDateTime.of(2026, 7, 23, 12, 0))),
                1));

    var response = service.getHistory(41L, 7L, " CHILD_PERSONAL_DATA ", from, to, 0, 20);

    assertThat(response.content()).hasSize(1);
    assertThat(response.content().getFirst().version()).isEqualTo("v2");
    assertThat(response.content().getFirst().recordedAt().toString())
        .isEqualTo("2026-07-23T12:00:00Z");
    assertThat(response.totalPages()).isEqualTo(1);
    assertThat(response.last()).isTrue();
  }

  @Test
  void rejectsHistoryForAnUnlinkedChildBeforeQueryingRecords() {
    when(authorizationRepository.hasGuardianChildRelation(41L, 7L)).thenReturn(false);

    assertThatThrownBy(() -> service.getHistory(41L, 7L, null, null, null, 0, 20))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConsentErrorCode.CONSENT_ACTOR_NOT_GUARDIAN);
    verifyNoInteractions(historyRepository);
  }

  @Test
  void queriesAllUserAndLinkedChildHistoryWhenChildFilterIsAbsent() {
    when(historyRepository.findAccessibleHistory(41L, null, null, null, null, 1, 10))
        .thenReturn(new ConsentHistoryPage(List.of(), 11));

    var response = service.getHistory(41L, null, " ", null, null, 1, 10);

    verify(historyRepository).findAccessibleHistory(41L, null, null, null, null, 1, 10);
    assertThat(response.totalPages()).isEqualTo(2);
    assertThat(response.first()).isFalse();
    assertThat(response.last()).isTrue();
    assertThat(response.hasNext()).isFalse();
  }
}
