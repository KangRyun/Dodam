package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportCrisisAlert;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 리포트 위기 대응 안내를 저장·조회하는 저장소다 (S15P11B209-902).
 *
 * <p>식별자가 리포트 식별자다({@code @MapsId}) — 리포트당 한 건을 구조로 보장한다.
 */
public interface ReportCrisisAlertRepository extends JpaRepository<ReportCrisisAlert, Long> {}
