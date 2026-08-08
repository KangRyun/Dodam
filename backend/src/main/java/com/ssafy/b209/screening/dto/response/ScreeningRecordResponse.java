package com.ssafy.b209.screening.dto.response;

import java.time.LocalDate;
import java.util.List;

/**
 * 보호자가 옮겨 적은 선별 결과 한 건이다.
 *
 * <p>화면은 이 값을 <strong>'보호자가 입력한 기록'으로만</strong> 보여 준다. {@code sourceVerified} 가 거짓이면 공식 결과가 아니며,
 * 지금은 공식 서비스 연동이 없어 언제나 거짓이다 — 미검증 기록을 공식 결과처럼 보여 주는 것이 이 기능에서 가장 위험한 실패다.
 *
 * @param recordId 기록 식별자
 * @param instrumentId 도구 식별자
 * @param instrumentDisplayName 등록부의 공식 도구명
 * @param instrumentVersion 결과지에 적힌 도구 버전이며 없으면 {@code null}
 * @param respondent 결과를 보고한 사람
 * @param completedAt 검사 실시일
 * @param sourceAuthorityType 결과를 발급한 곳의 성격
 * @param sourceAuthorityName 결과를 발급한 곳
 * @param sourceVerified 출처 검증 여부이며 현재 언제나 {@code false}
 * @param officialResultCode 결과지의 코드이며 없으면 {@code null}
 * @param officialResultText 결과 문구를 변경 없이
 * @param diagnosticStatus 선별은 진단이 아니라는 고정 표기
 * @param scoredBy 채점 주체
 * @param requiredDisclosure 등록부가 정한 필수 고지이며 <strong>결과와 항상 함께 나간다</strong>
 * @param domainResults 영역별 결과 라벨
 * @param followupLevel 다음 걸음이며 없으면 {@code null}
 * @param followupMessage 후속 안내이며 없으면 {@code null}
 * @param referralOptions 후속 상담 경로
 */
public record ScreeningRecordResponse(
    Long recordId,
    String instrumentId,
    String instrumentDisplayName,
    String instrumentVersion,
    String respondent,
    LocalDate completedAt,
    String sourceAuthorityType,
    String sourceAuthorityName,
    boolean sourceVerified,
    String officialResultCode,
    String officialResultText,
    String diagnosticStatus,
    String scoredBy,
    String requiredDisclosure,
    List<DomainResultResponse> domainResults,
    String followupLevel,
    String followupMessage,
    List<String> referralOptions) {

  /** 목록은 빈 목록으로 정규화한다. */
  public ScreeningRecordResponse {
    domainResults = domainResults == null ? List.of() : List.copyOf(domainResults);
    referralOptions = referralOptions == null ? List.of() : List.copyOf(referralOptions);
  }

  /**
   * 영역별 결과 한 줄이다.
   *
   * @param domainName 영역 이름
   * @param resultLabel 영역 결과 라벨
   */
  public record DomainResultResponse(String domainName, String resultLabel) {}
}
