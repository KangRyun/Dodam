package com.ssafy.b209.report.safety;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 경향 해석 안전 검증 테스트가 공유하는 입력 조립기다. */
final class InterpretationSafetyFixtures {

  /** 계약 §3 예시 그대로의 해석 범위 안내다. */
  static final String SCOPE_TEXT = "이번 그림 활동에서 나타난 가능성입니다.";

  /** 계약 §3 예시 그대로의 가정 관찰 안내다. */
  static final String HOME_GUIDE = "새로운 상황에서도 보호자의 확인을 반복해서 구하는지 살펴봐 주세요.";

  /** 계약 §3 예시 그대로의 가능성 어조 경향 문장이다. */
  static final String TENDENCY_TEXT = "가족에게 정서적으로 의지하려는 경향이 보일 수 있습니다.";

  private InterpretationSafetyFixtures() {}

  static InterpretationCandidate card(Long... evidenceRefs) {
    return cardWithTendency(TENDENCY_TEXT, evidenceRefs);
  }

  /**
   * 기본 카드다.
   *
   * <p>확신 등급은 {@code null}로 둔다 — 검증기는 등급을 읽지 않으므로(S15P11B209-982) 등급 없이도 모든 판정이 그대로 나와야 한다는 것이 이
   * fixture 의 전제다.
   */
  static InterpretationCandidate cardWithTendency(String tendencyText, Long... evidenceRefs) {
    return new InterpretationCandidate(
        InterpretationCategory.RELATIONSHIP,
        "가족과의 정서적 연결",
        tendencyText,
        SCOPE_TEXT,
        HOME_GUIDE,
        Arrays.asList(evidenceRefs),
        null);
  }

  /** {@code scopeText}만 갈아 끼운 카드다 — 나머지 문장은 안전하므로 판정은 이 필드에서만 나온다. */
  static InterpretationCandidate cardWithScope(String scopeText, Long... evidenceRefs) {
    return new InterpretationCandidate(
        InterpretationCategory.RELATIONSHIP,
        "가족과의 정서적 연결",
        TENDENCY_TEXT,
        scopeText,
        HOME_GUIDE,
        Arrays.asList(evidenceRefs),
        null);
  }

  static EvidenceSourceRef answerRef(String messageId) {
    return new EvidenceSourceRef(EvidenceSourceKind.QA_ANSWER, messageId);
  }

  static EvidenceSourceRef ref(EvidenceSourceKind kind, String id) {
    return new EvidenceSourceRef(kind, id);
  }

  static EvidenceCandidate childAnswer(long evidenceId, String messageId) {
    return EvidenceCandidate.source(
        evidenceId, EvidenceSourceType.CHILD_ANSWER, "아이의 답변입니다.", answerRef(messageId));
  }

  static EvidenceCandidate vision(long evidenceId, String detectedObjectId) {
    return EvidenceCandidate.source(
        evidenceId,
        EvidenceSourceType.VISION,
        "그림에서 확인한 내용입니다.",
        ref(EvidenceSourceKind.DETECTED_OBJECT, detectedObjectId));
  }

  static EvidenceCandidate selectedEmotion(long evidenceId, String rowId) {
    return EvidenceCandidate.source(
        evidenceId,
        EvidenceSourceType.SELECTED_EMOTION,
        "아이가 선택한 감정입니다.",
        ref(EvidenceSourceKind.EMOTION_SELECTION, rowId));
  }

  static EvidenceCandidate statedEmotion(long evidenceId, String messageId) {
    return EvidenceCandidate.source(
        evidenceId, EvidenceSourceType.STATED_EMOTION, "아이가 말한 감정입니다.", answerRef(messageId));
  }

  static EvidenceCandidate activityMetric(long evidenceId, String snapshotId) {
    return EvidenceCandidate.source(
        evidenceId,
        EvidenceSourceType.ACTIVITY_METRIC,
        "활동 기록입니다.",
        ref(EvidenceSourceKind.ACTIVITY_METRIC, snapshotId));
  }

  static EvidenceCandidate repeatedSubject(long evidenceId, EvidenceSourceRef... derivedFrom) {
    return EvidenceCandidate.derived(
        evidenceId,
        EvidenceSourceType.REPEATED_SUBJECT,
        "여러 그림에서 반복되었습니다.",
        Arrays.asList(derivedFrom));
  }

  static EvidenceCandidate longitudinal(long evidenceId, EvidenceSourceRef... derivedFrom) {
    return EvidenceCandidate.derived(
        evidenceId,
        EvidenceSourceType.LONGITUDINAL,
        "이전 활동에서도 나타났습니다.",
        Arrays.asList(derivedFrom));
  }

  static Map<Long, EvidenceCandidate> pool(EvidenceCandidate... items) {
    Map<Long, EvidenceCandidate> pool = new LinkedHashMap<>();
    for (EvidenceCandidate item : items) {
      pool.put(item.evidenceId(), item);
    }
    return pool;
  }

  static List<EvidenceCandidate> items(EvidenceCandidate... items) {
    return Arrays.asList(items);
  }
}
