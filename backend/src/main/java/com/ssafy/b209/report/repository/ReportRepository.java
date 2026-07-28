package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.Report;
import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 그림 활동 리포트의 생성 접수 저장과 분석별 조회를 담당한다. */
public interface ReportRepository extends JpaRepository<Report, Long> {

  /**
   * 세션에서 가장 최근 생성된 리포트를 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 생성 시각과 식별자 역순의 첫 번째 리포트, 없으면 빈 값
   */
  Optional<Report> findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(Long drawingSessionId);

  /**
   * Session에서 가장 높은 버전의 리포트를 조회한다.
   *
   * @param drawingSessionId 그림 활동 Session 식별자
   * @return 최신 리포트이며 생성된 적이 없으면 빈 값
   */
  Optional<Report> findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(Long drawingSessionId);

  /**
   * 여러 세션의 리포트를 세션·생성 시각·식별자 순으로 한 번에 조회한다.
   *
   * <p>목록 조회에서 세션마다 개별 조회를 하지 않고 배치로 읽어 조립하기 위한 경계다. 각 세션의 첫 항목이 가장 최근 리포트다.
   *
   * @param drawingSessionIds 그림 활동 세션 식별자 목록
   * @return 세션 식별자 오름차순, 생성 시각과 식별자 역순으로 정렬된 리포트 목록
   */
  List<Report> findByDrawingSessionIdInOrderByDrawingSessionIdAscCreatedAtDescIdDesc(
      List<Long> drawingSessionIds);

  /**
   * 최종 분석에 연결된 리포트를 조회한다.
   *
   * @param analysisId 최종 분석 식별자
   * @return 리포트를 요청하지 않았거나 생성되지 않았으면 빈 값
   */
  Optional<Report> findByAnalysisId(Long analysisId);

  /**
   * 리포트를 한 번만 완료 또는 실패 처리하도록 쓰기 잠금으로 조회한다.
   *
   * @param id 리포트 식별자
   * @return 잠근 리포트, 존재하지 않으면 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("select r from Report r where r.id = :id")
  Optional<Report> findByIdForUpdate(@Param("id") Long id);
}
