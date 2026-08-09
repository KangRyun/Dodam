import 'dart:typed_data';

/// 보호자에게 재생할 아동 음성 답변의 검증된 binary 응답.
final class VoiceAnswerAudio {
  const VoiceAnswerAudio({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

enum VoiceAnswerPlaybackValidationReason {
  invalidMessageId,
  emptyAudio,
  tooLarge,
  unsupportedMimeType,
  invalidResponse,
}

/// 같은 요청을 반복해도 회복되지 않는 음성 재생 응답 검증 실패.
final class VoiceAnswerPlaybackValidationFailure implements Exception {
  const VoiceAnswerPlaybackValidationFailure(this.reason);

  final VoiceAnswerPlaybackValidationReason reason;
}
