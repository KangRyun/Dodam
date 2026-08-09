package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryInsight;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기 V2 핵심 이야기의 저장을 담당한다. 리포트당 최대 하나이며 없는 것이 정상이다. */
public interface ReportDiaryInsightRepository extends JpaRepository<ReportDiaryInsight, Long> {}
