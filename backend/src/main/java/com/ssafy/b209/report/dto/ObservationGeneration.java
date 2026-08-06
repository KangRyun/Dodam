package com.ssafy.b209.report.dto;

/**
 * AI 가 준 관찰 생성 응답이다. <b>계약에 맞춰 읽은 결과와 원본 JSON 을 함께</b> 담는다.
 *
 * <p>{@link ObservationGenerationResult} 는 우리가 정한 스키마다. AI 가 그 밖의 필드를 더 보내면 읽는 순간 사라진다. 대부분은 그래도
 * 되지만, 집·나무·사람 활동에서는 <b>스키마에 담기지 않은 서술이 실제로 있는지, 무엇이 버려지는지</b> 보고 판단해야 한다(S15P11B209-980). 그래서 원본
 * 문자열을 그대로 함께 들고 다닌다.
 *
 * @param result 계약 스키마로 읽은 결과이며 이후 저장·표시는 모두 이 값을 쓴다
 * @param rawJson AI 응답 본문 그대로이며 받아 두지 못했으면 {@code null}
 */
public record ObservationGeneration(ObservationGenerationResult result, String rawJson) {}
