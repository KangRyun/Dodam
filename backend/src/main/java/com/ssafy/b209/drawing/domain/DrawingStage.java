package com.ssafy.b209.drawing.domain;

/** 그림 활동 세션이 진행하는 업무 단계를 표현한다. */
public enum DrawingStage {
  /** 아동이 그림을 작성하거나 제출하는 단계다. */
  DRAWING,
  /** 제출된 그림을 분석하는 단계다. */
  ANALYZING,
  /** 분석 결과를 바탕으로 대화하는 단계다. */
  CONVERSING,
  /** 활동 내용을 돌아보는 단계다. */
  REFLECTION,
  /** 활동 결과 보고서를 구성하는 단계다. */
  REPORTING,
  /** 모든 그림 활동 단계를 마친 단계다. */
  COMPLETED
}
