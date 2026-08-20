package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportDiaryTranscriptEntry;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;

class DiaryTranscriptSnapshotFactoryTest {

  private final DiaryTranscriptSnapshotFactory factory = new DiaryTranscriptSnapshotFactory();

  @Test
  void createsOrderedVoiceAndOptionSnapshotsWithoutPersistingStorageUrls() {
    Report report = mock(Report.class);
    LocalDateTime voiceCreatedAt = LocalDateTime.of(2026, 8, 9, 10, 15);
    LocalDateTime optionCreatedAt = voiceCreatedAt.plusMinutes(1);
    ObservationGenerationContext context =
        context(
            List.of(
                new ObservationGenerationContext.KeyConversationLine(
                    11L,
                    "그림 속 친구는 무엇을 하고 있어?",
                    21L,
                    "공원에서 놀고 있어요",
                    "VOICE_ANSWER",
                    false,
                    "SUCCESS",
                    true,
                    voiceCreatedAt),
                new ObservationGenerationContext.KeyConversationLine(
                    12L,
                    "그때 기분은 어땠어?",
                    22L,
                    "기뻤어요",
                    "OPTION_ANSWER",
                    false,
                    null,
                    false,
                    optionCreatedAt)));

    List<ReportDiaryTranscriptEntry> entries = factory.create(report, context);

    assertThat(entries).hasSize(2);
    assertThat(entries.get(0).getResponseType()).isEqualTo("VOICE");
    assertThat(entries.get(0).getSttStatus()).isEqualTo("SUCCESS");
    assertThat(entries.get(0).isAudioAvailableAtGeneration()).isTrue();
    assertThat(entries.get(0).getOccurredAt()).isEqualTo(voiceCreatedAt);
    assertThat(entries.get(1).getResponseType()).isEqualTo("OPTION");
    assertThat(entries.get(1).getSttStatus()).isNull();
    assertThat(entries.get(1).getDisplayOrder()).isEqualTo(1);
  }

  @Test
  void keepsUnconfirmedVoiceAsTranscriptButMarksItsSttStatus() {
    Report report = mock(Report.class);
    ObservationGenerationContext context =
        context(
            List.of(
                new ObservationGenerationContext.KeyConversationLine(
                    11L,
                    "누구와 함께 있었어?",
                    21L,
                    "친구랑 있었어요",
                    "VOICE_ANSWER",
                    true,
                    "SUCCESS",
                    true,
                    LocalDateTime.of(2026, 8, 9, 10, 15))));

    List<ReportDiaryTranscriptEntry> entries = factory.create(report, context);

    assertThat(entries)
        .singleElement()
        .extracting(ReportDiaryTranscriptEntry::getSttStatus)
        .isEqualTo("NEEDS_CONFIRMATION");
  }

  @Test
  void usesTheUncappedSubjectConversationForTheFullTranscript() {
    Report report = mock(Report.class);
    List<ObservationGenerationContext.KeyConversationLine> fullLines =
        java.util.stream.IntStream.range(0, 7)
            .mapToObj(
                index ->
                    new ObservationGenerationContext.KeyConversationLine(
                        10L + index,
                        "질문 " + index,
                        20L + index,
                        "답변 " + index,
                        "TEXT_ANSWER",
                        false))
            .toList();
    ObservationGenerationContext context =
        new ObservationGenerationContext(
            1L,
            2L,
            3L,
            4L,
            "STANDARD",
            7,
            7,
            0,
            0,
            List.of(),
            null,
            fullLines.subList(0, 5),
            List.of(
                new ObservationGenerationContext.SubjectContext(
                    null, null, List.of(), fullLines, null, List.of(), 2L)),
            List.of(),
            List.of(new ObservationGenerationContext.ActivitySessionRef(2L, null)),
            7);

    List<ReportDiaryTranscriptEntry> entries = factory.create(report, context);

    assertThat(entries).hasSize(7);
    assertThat(entries.get(6).getAnswerText()).isEqualTo("답변 6");
  }

  private ObservationGenerationContext context(
      List<ObservationGenerationContext.KeyConversationLine> lines) {
    return new ObservationGenerationContext(
        1L,
        2L,
        3L,
        4L,
        "STANDARD",
        lines.size(),
        lines.size(),
        0,
        0,
        List.of(),
        null,
        lines,
        List.of(),
        List.of(),
        List.of(new ObservationGenerationContext.ActivitySessionRef(2L, null)),
        7);
  }
}
