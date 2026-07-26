package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.conversation.exception.SttProcessingErrorCode;
import com.ssafy.b209.conversation.repository.SttVoiceAnswerMessageRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Pageable;

/** 정체된 PENDING 음성 답변의 회수 조건과 개별 실패 격리를 검증한다. */
@ExtendWith(MockitoExtension.class)
class SttPendingRecoverySchedulerTest {
  private static final Instant NOW = Instant.parse("2026-07-26T10:00:00Z");

  @Mock private SttVoiceAnswerMessageRepository messageRepository;
  @Mock private SttProcessingService sttProcessingService;

  private SttPendingRecoveryScheduler scheduler;

  @BeforeEach
  void setUp() {
    SttRecoveryProperties properties = new SttRecoveryProperties();
    properties.setMinimumAge(Duration.ofMinutes(2));
    properties.setBatchSize(5);
    scheduler =
        new SttPendingRecoveryScheduler(
            messageRepository, sttProcessingService, properties, Clock.fixed(NOW, ZoneOffset.UTC));
  }

  @Test
  void queriesOnlyMessagesOlderThanTheMinimumAgeWithinTheBatchSize() {
    given(messageRepository.findStalePendingIds(any(), any())).willReturn(List.of());

    scheduler.recoverStalePendingVoiceAnswers();

    ArgumentCaptor<LocalDateTime> thresholdCaptor = ArgumentCaptor.forClass(LocalDateTime.class);
    ArgumentCaptor<Pageable> pageableCaptor = ArgumentCaptor.forClass(Pageable.class);
    verify(messageRepository)
        .findStalePendingIds(thresholdCaptor.capture(), pageableCaptor.capture());
    assertThat(thresholdCaptor.getValue())
        .isEqualTo(LocalDateTime.ofInstant(NOW, ZoneOffset.UTC).minusMinutes(2));
    assertThat(pageableCaptor.getValue().getPageSize()).isEqualTo(5);
    verify(sttProcessingService, never()).process(any());
  }

  @Test
  void processesEveryStaleMessage() {
    given(messageRepository.findStalePendingIds(any(), any())).willReturn(List.of(11L, 12L));

    scheduler.recoverStalePendingVoiceAnswers();

    verify(sttProcessingService).process(11L);
    verify(sttProcessingService).process(12L);
  }

  @Test
  void continuesWithRemainingMessagesWhenOneRecoveryFails() {
    given(messageRepository.findStalePendingIds(any(), any())).willReturn(List.of(11L, 12L));
    willThrow(new BusinessException(SttProcessingErrorCode.INVALID_STT_MESSAGE))
        .given(sttProcessingService)
        .process(11L);

    assertThatCode(() -> scheduler.recoverStalePendingVoiceAnswers()).doesNotThrowAnyException();

    verify(sttProcessingService).process(12L);
  }
}
