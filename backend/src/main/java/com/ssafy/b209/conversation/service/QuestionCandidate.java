package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.dto.DetectedObject;
import com.ssafy.b209.conversation.dto.QuestionOption;
import java.util.List;

/**
 * 저장 직전에 확정된 AI 또는 템플릿 질문이다.
 *
 * <p>{@code reopenAllowed}는 질문 내용이 아니라 <b>이 요청이 끝난 대화를 다시 열어도 되는 활동인가</b>를 저장 계층에 실어 나른다. 활동 유형은 상위
 * 흐름이 이미 확정해 두었고, 저장은 세션 잠금 안에서 일어나므로 여기서 다시 조회하면 잠금을 쥔 채 쿼리를 하나 더 하게 된다 — 그래서 값으로 내려보낸다.
 *
 * <p><b>축약 생성자를 두지 않는다.</b> {@code reopenAllowed}를 조용히 {@code false}로 채우는 편의 생성자가 있으면, 나중에 재개 경로가 그
 * 생성자를 골랐을 때 재개가 아무 오류 없이 죽는다. fail-closed 라 위험하지는 않지만 원인을 찾기 어려운 함정이라, 모든 호출부가 값을 명시하게 둔다.
 *
 * @param questionText 아이에게 보일 질문 문장
 * @param options 선택지 Snapshot, 없으면 {@code null}
 * @param targetObject 질문이 가리키는 탐지 객체, 없으면 {@code null}
 * @param questionTemplateId 폴백 템플릿 식별자, AI 생성 질문이면 {@code null}
 * @param fallbackUsed 폴백 템플릿으로 만든 질문인지 여부
 * @param parentMessageId 이어받은 이전 답변 식별자, 최초 질문이면 {@code null}
 * @param reopenAllowed 끝난 대화를 다시 열어도 되는 활동(그림일기)인지 여부
 */
record QuestionCandidate(
    String questionText,
    List<QuestionOption> options,
    DetectedObject targetObject,
    Long questionTemplateId,
    boolean fallbackUsed,
    Long parentMessageId,
    boolean reopenAllowed) {}
