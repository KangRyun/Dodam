package com.ssafy.b209.conversation.dto;

/** 실제 저장된 AI 또는 템플릿 질문의 안전한 결과다. */
public record GeneratedQuestion(Long messageId, String questionText, boolean fallbackUsed) {}
