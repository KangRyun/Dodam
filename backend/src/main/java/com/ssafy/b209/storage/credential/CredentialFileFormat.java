package com.ssafy.b209.storage.credential;

import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.Locale;

enum CredentialFileFormat {
  PDF("application/pdf", "pdf"),
  JPEG("image/jpeg", "jpg"),
  PNG("image/png", "png");

  private final String contentType;
  private final String extension;

  CredentialFileFormat(String contentType, String extension) {
    this.contentType = contentType;
    this.extension = extension;
  }

  String contentType() {
    return contentType;
  }

  String extension() {
    return extension;
  }

  static CredentialFileFormat validate(StoreCredentialFileCommand command, long maxSize) {
    if (command == null || command.content() == null || command.content().length == 0) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_FILE_INVALID);
    }
    if (command.content().length > maxSize) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_FILE_TOO_LARGE);
    }
    CredentialFileFormat detected = detect(command.content());
    String declared = normalizeContentType(command.contentType());
    String extension = extension(command.originalFilename());
    if (detected == null
        || !detected.contentType.equals(declared)
        || !matchesExtension(detected, extension)) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_FILE_INVALID);
    }
    return detected;
  }

  private static CredentialFileFormat detect(byte[] content) {
    if (content.length >= 5
        && content[0] == '%'
        && content[1] == 'P'
        && content[2] == 'D'
        && content[3] == 'F'
        && content[4] == '-') return PDF;
    if (content.length >= 3
        && (content[0] & 0xff) == 0xff
        && (content[1] & 0xff) == 0xd8
        && (content[2] & 0xff) == 0xff) return JPEG;
    byte[] png = {(byte) 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a};
    if (content.length >= png.length) {
      boolean match = true;
      for (int index = 0; index < png.length; index++) match &= content[index] == png[index];
      if (match) return PNG;
    }
    return null;
  }

  private static boolean matchesExtension(CredentialFileFormat format, String extension) {
    return switch (format) {
      case PDF -> "pdf".equals(extension);
      case JPEG -> "jpg".equals(extension) || "jpeg".equals(extension);
      case PNG -> "png".equals(extension);
    };
  }

  private static String normalizeContentType(String value) {
    if (value == null) return "";
    int separator = value.indexOf(';');
    return (separator < 0 ? value : value.substring(0, separator)).trim().toLowerCase(Locale.ROOT);
  }

  private static String extension(String filename) {
    if (filename == null) return "";
    String normalized = filename.replace('\\', '/');
    int dot = normalized.lastIndexOf('.');
    return dot < 0 ? "" : normalized.substring(dot + 1).toLowerCase(Locale.ROOT);
  }
}
