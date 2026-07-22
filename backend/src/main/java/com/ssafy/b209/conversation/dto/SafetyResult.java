package com.ssafy.b209.conversation.dto;

/** AI 안전 필터의 최소 통과 정보다. */
public record SafetyResult(String status, String ruleVersion, String blockReasonCode) {}
