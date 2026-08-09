package com.ssafy.b209.infrastructure.ai.tts;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.conversation.dto.TtsToneProfile;
import com.ssafy.b209.storage.audio.AudioStorageProperties;
import com.ssafy.b209.storage.audio.LocalAudioStorage;
import com.ssafy.b209.storage.audio.StagedAudio;
import com.ssafy.b209.storage.audio.StoreAudioCommand;
import com.ssafy.b209.storage.audio.StoredAudio;
import java.io.ByteArrayInputStream;
import java.math.BigDecimal;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/** Mock 합성기가 저장 계층의 형식·길이 검증을 통과하는 재생 가능한 MP3를 생성하는지 확인한다. */
class MockAiTtsClientTest {

  private final MockAiTtsClient client = new MockAiTtsClient();

  @Test
  void synthesizesPlayableMp3(@TempDir Path storageRoot) {
    TtsSynthesis synthesis =
        client.synthesize(
            new TtsSynthesisCommand(
                "이 그림에서 무엇이 보이니?",
                "CHILD_FRIENDLY_01",
                speed(),
                TtsToneProfile.CHARACTER_DEFAULT_V1));

    assertThat(synthesis.audioFormat()).isEqualTo("mp3");
    assertThat(synthesis.audio()).isNotEmpty();
    assertThat(synthesis.audio()[0] & 0xFF).isEqualTo(0xFF);
    assertThat(synthesis.audio()[1] & 0xE0).isEqualTo(0xE0);

    LocalAudioStorage storage =
        new LocalAudioStorage(
            new AudioStorageProperties(storageRoot, 20_971_520L),
            Clock.fixed(Instant.parse("2026-07-24T00:00:00Z"), ZoneOffset.UTC));
    StagedAudio staged =
        storage.stage(
            new StoreAudioCommand(
                new ByteArrayInputStream(synthesis.audio()),
                synthesis.audio().length,
                "audio/mpeg",
                "synthesis.mp3"));
    StoredAudio stored = storage.promote(staged);

    assertThat(stored.durationMillis()).isPositive();
    assertThat(stored.contentType()).isEqualTo("audio/mpeg");
    assertThat(stored.storageKey()).endsWith(".mp3");
    assertThat(stored.storageKey().split("/")).hasSize(4);
  }

  @Test
  void rejectsBlankText() {
    assertThatThrownBy(
            () ->
                client.synthesize(
                    new TtsSynthesisCommand(
                        "  ", "V", speed(), TtsToneProfile.CHARACTER_DEFAULT_V1)))
        .isInstanceOf(AiTtsClientException.class);
  }

  private BigDecimal speed() {
    return new BigDecimal("0.95");
  }
}
