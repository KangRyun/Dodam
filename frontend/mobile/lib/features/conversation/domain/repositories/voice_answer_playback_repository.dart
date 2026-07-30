import 'dart:async';

import '../models/voice_answer_audio.dart';

/// 화면이 바뀌거나 재생을 멈출 때 진행 중인 음성 다운로드를 취소한다.
final class VoiceAnswerPlaybackCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// 저장된 아동 음성 답변을 인증된 Backend 경계에서 읽는다.
abstract interface class VoiceAnswerPlaybackRepository {
  Future<VoiceAnswerAudio> loadVoiceAnswerAudio(
    int messageId, {
    VoiceAnswerPlaybackCancellation? cancellation,
  });
}
