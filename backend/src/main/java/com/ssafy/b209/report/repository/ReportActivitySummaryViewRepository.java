package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportActivitySummaryView;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 활동·대화 집계 요약을 읽는 저장소다. */
public interface ReportActivitySummaryViewRepository
    extends JpaRepository<ReportActivitySummaryView, Long> {}
