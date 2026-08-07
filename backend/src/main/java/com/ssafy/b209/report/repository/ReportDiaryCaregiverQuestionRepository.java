package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryCaregiverQuestion;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기 V2 보호자 질문을 담당한다. */
public interface ReportDiaryCaregiverQuestionRepository
    extends JpaRepository<ReportDiaryCaregiverQuestion, Long> {

  /**
   * 리포트의 보호자 질문을 노출 순서대로 읽는다.
   *
   * @param reportId 리포트 식별자
   * @return 순서대로 정렬된 목록이며 없으면 빈 목록
   */
  List<ReportDiaryCaregiverQuestion> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
