package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryTranscriptEntry;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기 V3 대화 스냅샷을 저장하고 순서대로 조회한다. */
public interface ReportDiaryTranscriptEntryRepository
    extends JpaRepository<ReportDiaryTranscriptEntry, Long> {

  /**
   * @param reportId 리포트 식별자
   * @return 대화 순서대로 정렬된 질문·답변 스냅샷
   */
  List<ReportDiaryTranscriptEntry> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
