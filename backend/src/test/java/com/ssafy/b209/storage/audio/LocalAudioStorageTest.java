package com.ssafy.b209.storage.audio;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.global.exception.BusinessException;
import java.io.ByteArrayInputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/** 음성 전용 로컬 저장소의 실제 signature·길이·보상 삭제 경계를 검증한다. */
class LocalAudioStorageTest {
  @TempDir Path temporaryDirectory;

  @Test
  void stagesAndPromotesValidWavWithoutLeakingOriginalFilename() throws Exception {
    LocalAudioStorage storage = storage(20 * 1024 * 1024);
    byte[] wav = wav(1);

    StagedAudio staged =
        storage.stage(
            new StoreAudioCommand(
                new ByteArrayInputStream(wav), wav.length, "audio/wav", "child.wav"));
    StoredAudio stored = storage.promote(staged);

    assertThat(staged.durationMillis()).isEqualTo(1000);
    assertThat(stored.storageKey())
        .doesNotContain("child.wav")
        .doesNotContain(temporaryDirectory.toString());
    assertThat(Files.exists(temporaryDirectory.resolve(stored.storageKey()))).isTrue();
    storage.delete(stored.storageKey());
    assertThat(Files.exists(temporaryDirectory.resolve(stored.storageKey()))).isFalse();
  }

  @Test
  void rejectsDurationLongerThanSixtySeconds() {
    LocalAudioStorage storage = storage(20 * 1024 * 1024);
    byte[] wav = wav(61);

    assertThatThrownBy(
            () ->
                storage.stage(
                    new StoreAudioCommand(
                        new ByteArrayInputStream(wav), wav.length, "audio/wav", "answer.wav")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AudioStorageErrorCode.AUDIO_DURATION_EXCEEDED));
  }

  @Test
  void rejectsDeclaredMimeAndActualSignatureMismatch() {
    LocalAudioStorage storage = storage(20 * 1024 * 1024);
    byte[] wav = wav(1);

    assertThatThrownBy(
            () ->
                storage.stage(
                    new StoreAudioCommand(
                        new ByteArrayInputStream(wav), wav.length, "audio/mpeg", "answer.mp3")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AudioStorageErrorCode.INVALID_AUDIO_FILE));
  }

  @Test
  void rejectsActualStreamLargerThanConfiguredLimit() {
    LocalAudioStorage storage = storage(100);
    byte[] wav = wav(1);

    assertThatThrownBy(
            () ->
                storage.stage(
                    new StoreAudioCommand(
                        new ByteArrayInputStream(wav), wav.length, "audio/wav", "answer.wav")))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AudioStorageErrorCode.AUDIO_FILE_TOO_LARGE));
  }

  private LocalAudioStorage storage(long maxSize) {
    return new LocalAudioStorage(
        new AudioStorageProperties(temporaryDirectory, maxSize),
        Clock.fixed(Instant.parse("2026-07-23T00:00:00Z"), ZoneOffset.UTC));
  }

  private byte[] wav(int seconds) {
    int sampleRate = 8000;
    int dataLength = sampleRate * seconds;
    ByteBuffer buffer = ByteBuffer.allocate(44 + dataLength).order(ByteOrder.LITTLE_ENDIAN);
    buffer.put("RIFF".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
    buffer.putInt(36 + dataLength);
    buffer.put("WAVEfmt ".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
    buffer.putInt(16);
    buffer.putShort((short) 1);
    buffer.putShort((short) 1);
    buffer.putInt(sampleRate);
    buffer.putInt(sampleRate);
    buffer.putShort((short) 1);
    buffer.putShort((short) 8);
    buffer.put("data".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
    buffer.putInt(dataLength);
    return buffer.array();
  }
}
