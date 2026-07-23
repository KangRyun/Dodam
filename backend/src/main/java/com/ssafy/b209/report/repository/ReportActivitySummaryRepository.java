package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportActivitySummary;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 활동 요약의 저장을 담당한다. */
public interface ReportActivitySummaryRepository
    extends JpaRepository<ReportActivitySummary, Long> {}
