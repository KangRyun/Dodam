package com.ssafy.b209.report.domain;

/** 리포트 관찰 특징을 노출할 수 있는 대상 범위를 나타낸다. */
public enum ReportFeatureVisibility {
  /** 전문가 내부 검토 화면에만 노출하는 관찰 특징이다. */
  EXPERT_ONLY,
  /** 전문가 검토를 마쳐 보호자에게 노출할 수 있는 관찰 특징이다. */
  REVIEWED_GUARDIAN
}
