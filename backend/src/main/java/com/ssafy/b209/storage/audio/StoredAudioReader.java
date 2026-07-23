package com.ssafy.b209.storage.audio;

/** 288이 보관한 음성 파일을 289 내부 STT 요청용으로 읽는 전용 경계다. */
public interface StoredAudioReader {

  /**
   * Root-relative storage key의 일반 파일을 읽기 전용 Stream으로 연다.
   *
   * @param storageKey DB에 저장된 Root-relative 음성 key
   * @return 원본 이름·절대 경로를 포함하지 않는 Stream 정보
   */
  OpenedAudio open(String storageKey);
}
