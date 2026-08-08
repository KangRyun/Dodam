package com.ssafy.b209.screening.dto.request;

import com.ssafy.b209.screening.domain.ScreeningFollowupLevel;
import com.ssafy.b209.screening.domain.ScreeningRespondent;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PastOrPresent;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.util.List;

/**
 * 보호자가 다른 곳에서 받은 선별 결과를 옮겨 적는 요청이다.
 *
 * <p><strong>문항 응답을 받지 않는다.</strong> 이 API 는 검사를 실시하지 않으며, 이미 나온 결과의 라벨과 출처만 기록한다 — 문항을 받는 순간 라이선스
 * 없는 검사 실시가 된다.
 *
 * <p>출처 검증 여부와 AI 재계산 여부도 받지 않는다. 둘 다 언제나 거짓이고, 클라이언트가 정할 수 있으면 검증되지 않은 기록이 공식 결과로 올라간다.
 *
 * @param instrumentId 등록부 allow-list 안의 도구 식별자
 * @param instrumentVersion 결과지에 적힌 도구 버전이며 없으면 {@code null}
 * @param respondent 결과를 보고한 사람
 * @param completedAt 검사 실시일이며 미래일 수 없다
 * @param childAgeMonthsAtAdministration 실시 당시 개월 나이이며 모르면 {@code null}
 * @param sourceAuthorityName 결과를 발급한 곳
 * @param officialResultCode 결과지의 코드이며 없으면 {@code null}
 * @param officialResultText 결과 문구를 <strong>변경 없이</strong> 옮긴 값
 * @param scoredBy 채점 주체이며 이 서비스는 절대 아니다
 * @param domainResults 영역별 결과 라벨이며 점수가 아니다
 * @param followupLevel 결과지에 적힌 다음 걸음이며 없으면 {@code null}
 * @param followupMessage 후속 안내이며 없으면 {@code null}
 * @param referralOptions 후속 상담 경로
 * @param sourceDocumentRef 원본 문서 참조이며 없으면 {@code null}
 * @param consentRecordId 임상 기록 보관 동의 이력 식별자. 서버가 이 이력을 직접 확인한다
 */
public record RegisterScreeningRecordRequest(
    @NotBlank @Size(max = 40) String instrumentId,
    @Size(max = 60) String instrumentVersion,
    @NotNull ScreeningRespondent respondent,
    @NotNull @PastOrPresent LocalDate completedAt,
    Integer childAgeMonthsAtAdministration,
    @NotBlank @Size(max = 150) String sourceAuthorityName,
    @Size(max = 60) String officialResultCode,
    @NotBlank @Size(max = 500) String officialResultText,
    @NotBlank @Size(max = 30) String scoredBy,
    List<@NotNull DomainResult> domainResults,
    ScreeningFollowupLevel followupLevel,
    @Size(max = 500) String followupMessage,
    List<@NotBlank @Size(max = 120) String> referralOptions,
    @Size(max = 300) String sourceDocumentRef,
    @NotNull @Positive Long consentRecordId) {

  /** 목록은 빈 목록으로 정규화한다. */
  public RegisterScreeningRecordRequest {
    domainResults = domainResults == null ? List.of() : List.copyOf(domainResults);
    referralOptions = referralOptions == null ? List.of() : List.copyOf(referralOptions);
  }

  /**
   * 영역별 결과 한 줄이다.
   *
   * <p>점수가 아니라 <strong>라벨</strong>만 받는다. 숫자를 받아 두면 어느 화면에선가 비교하거나 등급을 매기게 되고, 그건 이 서비스에 없는 권한이다.
   *
   * @param domainName 영역 이름을 결과지 그대로
   * @param resultLabel 영역 결과 라벨을 결과지 그대로
   */
  public record DomainResult(
      @NotBlank @Size(max = 60) String domainName, @NotBlank @Size(max = 120) String resultLabel) {}
}
