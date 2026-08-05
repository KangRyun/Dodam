package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportHtpStepView;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 리포트가 다루는 HTP 묶음의 형제 단계를 세는 저장소다 (S15P11B209-960). */
public interface ReportHtpStepViewRepository extends JpaRepository<ReportHtpStepView, Long> {

  /**
   * 이 그림 활동 세션이 속한 HTP 묶음의 단계 수를 센다.
   *
   * <p>875 §8 {@code aggregatedHtp} 판정에 쓴다. 값이 2 이상이면 리포트의 활동 수치가 <b>여러 활동을 합친 기록</b>이라는 뜻이고, 화면이
   * "집·나무·사람 세 활동을 합친 기록입니다"를 덧붙인다 — 합산 사실을 밝히지 않으면 보호자가 한 장을 그리는 데 걸린 시간으로 읽는다.
   *
   * <p>HTP 묶음에 속하지 않은 단독 세션은 0 이다.
   *
   * @param drawingSessionId 리포트가 가리키는 그림 활동 세션 식별자
   * @return 같은 묶음에 속한 단계 수이며 묶음이 없으면 0
   */
  @Query(
      "select count(sibling) from ReportHtpStepView self, ReportHtpStepView sibling "
          + "where self.drawingSessionId = :drawingSessionId "
          + "and sibling.assessmentId = self.assessmentId")
  long countStepsSharingAssessment(@Param("drawingSessionId") Long drawingSessionId);
}
