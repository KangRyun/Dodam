package com.ssafy.b209.report.service;

import java.util.List;

/**
 * 리포트 PDF 한 섹션 안에 들어가는 줄의 종류다.
 *
 * <p>화면은 라벨과 값, 감정 칩, 불릿 목록, 근거 캡션을 서로 다르게 보여 준다. 종류를 구분해 두지 않으면 PDF 는 전부 같은 줄글이 되어 무엇이 값이고 무엇이
 * 근거인지 읽을 수 없다.
 */
sealed interface ReportPdfRow {

  /** 본문 문단이다. 폭에 맞춰 여러 줄로 나뉜다. */
  record Text(String value) implements ReportPdfRow {}

  /** 앞에 점을 붙이는 목록 항목이다. */
  record Bullet(String value) implements ReportPdfRow {}

  /** 라벨과 값을 한 줄에 나란히 둔다. 활동 기록처럼 짝으로 읽는 값에 쓴다. */
  record KeyValue(String label, String value) implements ReportPdfRow {}

  /** 감정처럼 짧은 낱말을 알약 모양으로 늘어놓는다. */
  record Chips(List<String> labels) implements ReportPdfRow {}

  /** 근거·출처처럼 본문보다 작고 흐리게 두는 보조 설명이다. */
  record Caption(String value) implements ReportPdfRow {}

  /** 소제목이다. 카드 안에서 묶음을 나눈다. */
  record Subtitle(String value) implements ReportPdfRow {}
}
