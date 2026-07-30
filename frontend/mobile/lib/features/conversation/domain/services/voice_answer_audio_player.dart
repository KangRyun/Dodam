import 'dart:typed_data';

typedef VoiceAnswerAudioPlayerFactory = VoiceAnswerAudioPlayer Function();

/// 아동 답변 binary를 재생하는 low-level player 경계.
///
/// 질문 TTS와 lifecycle·상태를 공유하지 않도록 별도 책임으로 둔다.
abstract interface class VoiceAnswerAudioPlayer {
  /// 재생이 완료되거나 [stop]으로 중단될 때 완료된다.
  Future<void> play(Uint8List bytes, {required String mimeType});

  Future<void> stop();

  Future<void> dispose();
}
