package com.ssafy.b209.drawing.document;

import java.math.BigDecimal;
import java.util.List;

/**
 * 배치 안의 단일 그리기·편집 행위와 좌표 목록을 MongoDB 문서에 내장한다.
 *
 * <p>MySQL 시절의 {@code stroke_events} 1행에 대응한다. 배치와 조인할 일이 없고 항상 "세션 단위로 통째 재생"만 하므로 별도 컬렉션이 아니라 배치
 * 문서 안에 배열로 둔다.
 *
 * @param strokeSeq 세션 전체에서 증가하는 이벤트 순번
 * @param eventType 이벤트 유형 코드
 * @param tool 그리기 도구 코드, 없으면 {@code null}
 * @param color RGB 또는 RGBA Hex 색상, 없으면 {@code null}
 * @param width 선 굵기, 없으면 {@code null}
 * @param pressure 이벤트 대표 필압, 없으면 {@code null}
 * @param points 이벤트 내부 좌표 목록. UNDO 처럼 좌표가 없는 이벤트는 빈 목록
 */
public record StrokeEventDocument(
    long strokeSeq,
    String eventType,
    String tool,
    String color,
    BigDecimal width,
    BigDecimal pressure,
    List<StrokePointDocument> points) {}
