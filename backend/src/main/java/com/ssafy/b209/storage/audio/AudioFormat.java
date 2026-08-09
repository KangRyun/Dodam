package com.ssafy.b209.storage.audio;

import com.ssafy.b209.global.exception.BusinessException;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Set;

/** 허용된 음성 컨테이너와 MIME·확장자·시그니처 교차 검증 규칙이다. */
enum AudioFormat {
  WEBM("audio/webm", "webm", Set.of("audio/webm", "video/webm"), Set.of("webm")),
  M4A("audio/mp4", "m4a", Set.of("audio/mp4", "audio/x-m4a", "video/mp4"), Set.of("m4a", "mp4")),
  WAV("audio/wav", "wav", Set.of("audio/wav", "audio/x-wav", "audio/wave"), Set.of("wav")),
  MP3("audio/mpeg", "mp3", Set.of("audio/mpeg", "audio/mp3"), Set.of("mp3"));

  private final String canonicalContentType;
  private final String extension;
  private final Set<String> acceptedContentTypes;
  private final Set<String> acceptedExtensions;

  AudioFormat(
      String canonicalContentType,
      String extension,
      Set<String> acceptedContentTypes,
      Set<String> acceptedExtensions) {
    this.canonicalContentType = canonicalContentType;
    this.extension = extension;
    this.acceptedContentTypes = acceptedContentTypes;
    this.acceptedExtensions = acceptedExtensions;
  }

  static AudioFormat fromDeclared(String contentType, String originalFilename) {
    if (contentType == null || originalFilename == null || originalFilename.isBlank()) {
      throw new BusinessException(AudioStorageErrorCode.INVALID_AUDIO_FILE);
    }
    String normalized = contentType.trim().toLowerCase(Locale.ROOT);
    int dot = originalFilename.lastIndexOf('.');
    if (dot < 0 || dot == originalFilename.length() - 1) {
      throw new BusinessException(AudioStorageErrorCode.INVALID_AUDIO_FILE);
    }
    String extension = originalFilename.substring(dot + 1).toLowerCase(Locale.ROOT);
    for (AudioFormat format : values()) {
      if (format.acceptedContentTypes.contains(normalized)
          && format.acceptedExtensions.contains(extension)) {
        return format;
      }
    }
    throw new BusinessException(AudioStorageErrorCode.UNSUPPORTED_AUDIO_FORMAT);
  }

  static String contentTypeForExtension(String extension) {
    if (extension == null) {
      return null;
    }
    String normalized = extension.trim().toLowerCase(Locale.ROOT);
    for (AudioFormat format : values()) {
      if (format.acceptedExtensions.contains(normalized)) {
        return format.canonicalContentType;
      }
    }
    return null;
  }

  static AudioFormat detect(byte[] header, int length) {
    if (length >= 4
        && (header[0] & 0xFF) == 0x1A
        && (header[1] & 0xFF) == 0x45
        && (header[2] & 0xFF) == 0xDF
        && (header[3] & 0xFF) == 0xA3) {
      return WEBM;
    }
    if (length >= 12 && ascii(header, 0, 4).equals("RIFF") && ascii(header, 8, 4).equals("WAVE")) {
      return WAV;
    }
    if (length >= 12 && ascii(header, 4, 4).equals("ftyp")) {
      return M4A;
    }
    if (length >= 3 && ascii(header, 0, 3).equals("ID3")
        || length >= 2 && (header[0] & 0xFF) == 0xFF && (header[1] & 0xE0) == 0xE0) {
      return MP3;
    }
    return null;
  }

  String contentType() {
    return canonicalContentType;
  }

  String extension() {
    return extension;
  }

  private static String ascii(byte[] source, int offset, int count) {
    return new String(source, offset, count, StandardCharsets.US_ASCII);
  }
}
