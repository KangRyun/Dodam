package com.ssafy.b209.conversation.dto;

/** 외부 앱에 노출하는 질문 선택지 Snapshot이다. */
public record NextQuestionOptionResponse(
    String optionId, String type, String label, String value, String emoji) {}
