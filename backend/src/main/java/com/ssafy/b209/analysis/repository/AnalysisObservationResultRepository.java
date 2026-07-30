package com.ssafy.b209.analysis.repository;

import com.ssafy.b209.analysis.domain.AnalysisObservationResult;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 분석 관찰 결과의 저장과 분석별 존재 여부 확인을 담당한다. */
public interface AnalysisObservationResultRepository
    extends JpaRepository<AnalysisObservationResult, Long> {

  /**
   * 분석에 이미 저장된 관찰 결과가 있는지 확인한다.
   *
   * @param analysisId 최종 분석 식별자
   * @return 관찰 결과가 존재하면 {@code true}
   */
  boolean existsByAnalysisId(Long analysisId);

  /**
   * 분석의 그림 서술(VLM 관찰 요약)을 조회한다(S15P11B209-704).
   *
   * <p>질문 생성 프롬프트의 재료로만 쓴다. 같은 분석에 결과가 여러 세대 쌓일 수 있어 {@code resultVersion}이 가장 큰 것을 고른다 — 재분석했다면 최신
   * 서술로 질문해야 한다.
   *
   * <p>⚠️ 이 값은 보호자에게 그대로 노출하지 않는 초안이다(전문가 검토 전). LLM 입력으로만 쓰고 화면에 직접 내보내지 말 것.
   *
   * @param analysisId 근거 분석 식별자
   * @return 서술 문자열. 결과가 없거나 서술이 비어 있으면 빈 Optional
   */
  @Query(
      "select r.overallSummary from AnalysisObservationResult r "
          + "where r.analysis.id = :analysisId and r.overallSummary is not null "
          + "order by r.resultVersion desc limit 1")
  Optional<String> findLatestOverallSummary(@Param("analysisId") Long analysisId);

  /**
   * 그림 활동 세션의 가장 최근 관찰 결과(서술이 있는 것)를 조회한다(S15P11B209-741).
   *
   * <p>관찰 리포트 요청의 주제별 서술·탐지 코드 재료다. 세션에 분석이 여러 번 쌓일 수 있어(재분석·FINAL) 분석 식별자와 {@code resultVersion}
   * 역순으로 최신 하나를 고른다 — 서술이 비어 있는 결과(FINAL 직후 등)는 건너뛴다. 탐지 객체는 이 결과가 속한 분석({@code r.analysis})의 것을 함께
   * 쓴다.
   *
   * <p>⚠️ 이 값은 보호자에게 그대로 노출하지 않는 초안이다(전문가 검토 전). LLM 입력으로만 쓴다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 최신 관찰 결과. 서술 있는 결과가 없으면 빈 Optional
   */
  @Query(
      "select r from AnalysisObservationResult r "
          + "where r.analysis.drawingSession.id = :drawingSessionId "
          + "and r.overallSummary is not null "
          + "order by r.analysis.id desc, r.resultVersion desc limit 1")
  Optional<AnalysisObservationResult> findLatestByDrawingSessionId(
      @Param("drawingSessionId") Long drawingSessionId);
}
