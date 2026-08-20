package com.ssafy.b209.report.service;

import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportDiaryTranscriptEntry;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.stream.Stream;
import org.springframework.stereotype.Component;

/**
 * 리포트 생성 맥락의 질문·답변을 변경 불가능한 그림일기 대화 스냅샷으로 변환한다.
 *
 * <p>AI 출력에 의존하지 않고 서버가 조회한 메시지 식별자와 상태만 사용한다. 음성 URL과 Storage Key는 저장하지 않으며, 현재 수집하지 않는 음성 길이도
 * 추정하지 않는다.
 */
@Component
public class DiaryTranscriptSnapshotFactory {

  /**
   * 생성 맥락에 포함된 전체 대표 대화를 순서대로 변환한다.
   *
   * @param report 스냅샷이 속할 리포트
   * @param context 서버가 수집한 생성 맥락
   * @return 표시 순서가 고정된 대화 스냅샷 목록
   */
  public List<ReportDiaryTranscriptEntry> create(
      Report report, ObservationGenerationContext context) {
    List<ReportDiaryTranscriptEntry> entries = new ArrayList<>();
    List<ObservationGenerationContext.KeyConversationLine> subjectLines =
        context.subjectContexts().stream()
            .flatMap(subject -> safeStream(subject.qaPairs()))
            .toList();
    // keyConversations는 대표 노출용 5건 상한이 있다. 전체 대화 스냅샷은 주제 맥락의 무제한 문답을
    // 우선 사용하고, 과거 호출부처럼 주제 맥락이 없을 때만 대표 문답으로 폴백한다.
    List<ObservationGenerationContext.KeyConversationLine> lines =
        subjectLines.isEmpty() ? context.keyConversations() : subjectLines;
    for (int index = 0; index < lines.size(); index++) {
      ObservationGenerationContext.KeyConversationLine line = lines.get(index);
      String responseType = responseType(line.answerType());
      String sttStatus = sttStatus(line, responseType);
      entries.add(
          ReportDiaryTranscriptEntry.create(
              report,
              line.questionMessageId(),
              line.answerMessageId(),
              line.questionText(),
              line.answerText(),
              responseType,
              sttStatus,
              line.audioAvailableAtGeneration(),
              null,
              elicitationType(responseType),
              line.answerCreatedAt(),
              index));
    }
    return List.copyOf(entries);
  }

  private Stream<ObservationGenerationContext.KeyConversationLine> safeStream(
      List<ObservationGenerationContext.KeyConversationLine> lines) {
    return lines == null ? Stream.empty() : lines.stream();
  }

  private String responseType(String answerType) {
    if (answerType == null) {
      return "SKIPPED";
    }
    return switch (answerType.toUpperCase(Locale.ROOT)) {
      case "VOICE_ANSWER" -> "VOICE";
      case "OPTION_ANSWER" -> "OPTION";
      case "TEXT_ANSWER" -> "TEXT";
      default -> "SKIPPED";
    };
  }

  private String sttStatus(
      ObservationGenerationContext.KeyConversationLine line, String responseType) {
    if (!"VOICE".equals(responseType)) {
      return null;
    }
    if (line.sttNeedsConfirmation()) {
      return "NEEDS_CONFIRMATION";
    }
    return line.speechStatus();
  }

  private String elicitationType(String responseType) {
    return "OPTION".equals(responseType) ? "MULTIPLE_CHOICE" : "OPEN_INVITATION";
  }
}
