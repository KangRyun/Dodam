package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryChildVoice;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기 V2 아이 발화를 담당한다. */
public interface ReportDiaryChildVoiceRepository
    extends JpaRepository<ReportDiaryChildVoice, Long> {

  /**
   * 리포트에 담긴 아이 발화를 노출 순서대로 읽는다.
   *
   * @param reportId 리포트 식별자
   * @return 순서대로 정렬된 목록이며 없으면 빈 목록
   */
  List<ReportDiaryChildVoice> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
