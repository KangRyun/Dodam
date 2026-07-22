package com.ssafy.b209.conversation.dto;

/** 외부 앱에 노출하는 0~1 정규화 대상 객체 영역이다. */
public record NextQuestionBoundingBoxResponse(double x, double y, double width, double height) {}
