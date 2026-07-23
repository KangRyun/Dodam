package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportObservedFeature;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 관찰 특징의 저장을 담당한다. */
public interface ReportObservedFeatureRepository
    extends JpaRepository<ReportObservedFeature, Long> {}
