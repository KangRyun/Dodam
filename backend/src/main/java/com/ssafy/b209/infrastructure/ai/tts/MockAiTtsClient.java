package com.ssafy.b209.infrastructure.ai.tts;

import java.io.ByteArrayOutputStream;

/**
 * 실제 AI 서버를 호출하지 않고 후속 흐름 개발용으로 재생 가능한 MP3를 합성하는 Client다.
 *
 * <p>반환 값은 결정적인 무음 MPEG-1 Layer III 프레임이며 실제 음성 콘텐츠를 담지 않는다. 저장 계층의 형식·길이 검증을 그대로 통과하도록 유효한 프레임만
 * 생성한다. 음색·속도는 계약 전달만 확인하고 파형에는 반영하지 않는다.
 */
public final class MockAiTtsClient implements AiTtsClient {

  private static final String AUDIO_FORMAT = "mp3";
  private static final int FRAME_LENGTH = 417;
  private static final int MIN_FRAMES = 20;
  private static final int MAX_FRAMES = 400;
  private static final byte[] FRAME_HEADER = {(byte) 0xFF, (byte) 0xFB, (byte) 0x90, (byte) 0x00};

  /**
   * 검증된 요청을 받아 결정적인 무음 MP3를 합성한다.
   *
   * @param command 합성할 텍스트와 음색·속도 요청
   * @return 재생 가능한 무음 MP3 Byte와 {@code mp3} 형식
   * @throws AiTtsClientException 합성할 텍스트가 비어 있는 경우
   */
  @Override
  public TtsSynthesis synthesize(TtsSynthesisCommand command) {
    if (command == null || command.text() == null || command.text().isBlank()) {
      throw new AiTtsClientException(AiTtsClientException.Type.REQUEST_FAILED);
    }
    int frames = Math.min(MAX_FRAMES, Math.max(MIN_FRAMES, command.text().length()));
    return new TtsSynthesis(silentMp3(frames), AUDIO_FORMAT);
  }

  private byte[] silentMp3(int frames) {
    ByteArrayOutputStream output = new ByteArrayOutputStream(frames * FRAME_LENGTH);
    for (int frame = 0; frame < frames; frame++) {
      output.write(FRAME_HEADER, 0, FRAME_HEADER.length);
      for (int index = FRAME_HEADER.length; index < FRAME_LENGTH; index++) {
        output.write(0);
      }
    }
    return output.toByteArray();
  }
}
