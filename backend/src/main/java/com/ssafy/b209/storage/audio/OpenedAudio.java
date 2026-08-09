package com.ssafy.b209.storage.audio;

import java.io.InputStream;

/**
 * 내부 AI 호출에만 전달하는 저장된 음성 Stream과 안전한 전송 파일명이다.
 *
 * <p>파일명은 원본 업로드 파일명이 아니라 storage key의 확장자에서 만든 일반 이름이다.
 *
 * @param inputStream 호출 종료 후 닫아야 하는 음성 Stream
 * @param transferFilename 내부 multipart에만 쓰는 비식별 파일명
 */
public record OpenedAudio(InputStream inputStream, String transferFilename)
    implements AutoCloseable {

  /** 내부 HTTP 전송이 끝난 뒤 파일 Stream을 닫는다. */
  @Override
  public void close() throws java.io.IOException {
    inputStream.close();
  }
}
