package com.ssafy.b209.conversation.dto;

/** AI 질문 요청에 제공하는 탐지 객체다. */
public record DetectedObject(
    String objectCode, String objectName, double confidence, BoundingBox boundingBox) {}
