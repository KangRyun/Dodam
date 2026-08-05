package com.ssafy.b209.report.safety;

import java.util.regex.Pattern;

/**
 * 근거 원본 식별자({@code sourceRef.id})가 <strong>단일 식별자</strong> 형태인지 판정한다(875 계약 §4).
 *
 * <p>막으려는 것은 <strong>조합키</strong>다. 생성자가 {@code analysisId + objectCode + detectionOrder}처럼 값을 조립할
 * 수 있으면 "서로 독립된 근거 2건"을 스스로 만들어 낼 수 있어 게이트가 자기 신고로 무력해진다.
 *
 * <p><strong>규칙의 근거 — AI에는 조합키 판정이 없다.</strong> {@code ai/internal_contracts.py}의 {@code
 * EvidenceSourceRef}는 {@code kind: str}·{@code id: str}뿐이고 검증자가 없다. 실제 검사는 {@code
 * ai/report_client.py}의 {@code _source_ref}가 하는 <em>{@code kind} 화이트리스트 + {@code id} 비어 있지 않음</em>
 * 두 가지뿐이며(주석은 "조합키·창작 차단"이라 적혀 있으나 코드는 조합 형태를 보지 않는다), {@code ai/interpretation_gate.py}는 형태를 전혀 보지
 * 않는다. 그래서 아래 규칙은 AI 코드에서 그대로 가져올 수 없고, 두 사실만을 근거로 최소한으로 둔다.
 *
 * <ol>
 *   <li><strong>숫자 전용 규칙을 쓰지 않는다.</strong> 저장 스키마가 {@code source_ref_id VARCHAR(64)} 문자열이고(V37), AI
 *       픽스처가 {@code "m1"}·{@code "d1"}·{@code "v1"} 같은 비숫자 식별자를 쓴다. 숫자만 허용하면 활동 지표·탐지 객체를 쓰는 카드가 전부
 *       제외된다.
 *   <li><strong>구분자로 여러 조각을 이어 붙인 형태만 거부한다.</strong> 조합키가 성립하려면 파트 구분자가 필요하다.
 * </ol>
 *
 * <p>거부 예: {@code "12:HOUSE:3"} · {@code "12|3"} · {@code "a/b"} · {@code "12+HOUSE"} · {@code "102
 * "}(공백 포함) · 빈 문자열 · 64자 초과.
 *
 * <p><strong>남는 구멍(의도적):</strong> {@code -}와 {@code _}는 구분자로 보지 않는다. 하나의 BE 발급 식별자 안에 정상적으로 등장하기
 * 때문이다(UUID·슬러그). 그래서 {@code "884-HOUSE-3"} 형태의 조합키는 이 검사를 통과한다. 이 층에서 더 조이면 정상 식별자를 함께 막게 되므로, 그
 * 구멍은 참조가 실제 행을 가리키는지 DB에서 확인하는 단계에서 닫아야 한다.
 */
final class EvidenceSourceIdentifiers {

  /** 저장 컬럼 {@code report_evidence_items.source_ref_id}의 길이다(V37). */
  private static final int MAX_LENGTH = 64;

  /** 조합키를 만들 때 쓰이는 파트 구분자와 공백이다. {@code -}·{@code _}는 단일 식별자에도 쓰이므로 넣지 않는다. */
  private static final Pattern PART_SEPARATOR = Pattern.compile("[\\s:|/\\\\#,;+=&@]");

  private EvidenceSourceIdentifiers() {}

  /**
   * 식별자 문자열이 단일 식별자 형태인지 판정한다.
   *
   * @param id 검사할 식별자 문자열이며 없으면 {@code null}
   * @return 단일 식별자 형태면 {@code true}
   */
  static boolean isSingleIdentifier(String id) {
    if (id == null || id.isEmpty() || id.length() > MAX_LENGTH) {
      return false;
    }
    return !PART_SEPARATOR.matcher(id).find();
  }
}
