package com.ssafy.b209.conversation.dto;

/** 외부 앱에 노출하는 질문 대상 객체 Snapshot이다. */
public record NextQuestionTargetResponse(
    String objectCode, String objectName, NextQuestionBoundingBoxResponse boundingBox) {}
