package com.ssafy.b209.child.domain;

/** 보호자가 아동을 등록할 때 선택하는 보호자와 아동의 관계 유형이다. */
public enum GuardianRelationshipType {
  /** 어머니. */
  MOTHER,
  /** 아버지. */
  FATHER,
  /** 조부모. */
  GRANDPARENT,
  /** 법적 보호자 또는 후견인. */
  GUARDIAN,
  /** 위 유형에 속하지 않는 기타 관계. */
  OTHER
}
