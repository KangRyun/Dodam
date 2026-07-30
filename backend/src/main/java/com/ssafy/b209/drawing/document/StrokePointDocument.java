package com.ssafy.b209.drawing.document;

import java.math.BigDecimal;
import org.springframework.data.mongodb.core.mapping.Field;

/**
 * Stroke 이벤트 내부의 정규화된 단일 좌표를 MongoDB 문서에 내장한다.
 *
 * <p>필드 이름을 한 글자로 줄인다. 좌표는 배치 하나에 최대 20,000개가 들어가는데 BSON 은 문서마다 필드 이름을 그대로 저장하므로, 이름 길이가 곧 저장 용량이다.
 * MySQL 의 {@code stroke_event_points} 는 좌표 1개가 1행이었고 그 행 폭증이 이 이관의 이유였다.
 *
 * @param x 0 이상 1 이하의 정규화 X 좌표
 * @param y 0 이상 1 이하의 정규화 Y 좌표
 * @param elapsedMs 이벤트 시작 후 경과 시간(ms)
 * @param pressure 기기가 제공한 필압, 미지원이면 {@code null}
 */
public record StrokePointDocument(
    @Field("x") BigDecimal x,
    @Field("y") BigDecimal y,
    @Field("t") long elapsedMs,
    @Field("p") BigDecimal pressure) {}
