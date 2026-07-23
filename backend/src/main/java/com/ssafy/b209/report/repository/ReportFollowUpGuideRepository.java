package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportFollowUpGuide;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 후속 안내의 저장을 담당한다. */
public interface ReportFollowUpGuideRepository extends JpaRepository<ReportFollowUpGuide, Long> {}
