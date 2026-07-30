import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/network.dart';
import '../domain/models/voice_answer_audio.dart';
import '../domain/repositories/voice_answer_playback_repository.dart';
import '../domain/services/voice_answer_audio_player.dart';

enum VoiceAnswerPlaybackStatus {
  idle,
  loading,
  playing,
  stopped,
  completed,
  failure,
}

/// 보호자 화면의 모든 음성 답변에서 재생 하나만 활성화한다.
final class VoiceAnswerPlaybackController extends ChangeNotifier {
  VoiceAnswerPlaybackController(this._repository, this._player);

  final VoiceAnswerPlaybackRepository _repository;
  final VoiceAnswerAudioPlayer _player;

  VoiceAnswerPlaybackStatus status = VoiceAnswerPlaybackStatus.idle;
  int? activeMessageId;
  Object? error;
  int _generation = 0;
  bool _disposed = false;
  VoiceAnswerPlaybackCancellation? _loadCancellation;

  bool get canRetry =>
      status == VoiceAnswerPlaybackStatus.failure &&
      error is! VoiceAnswerPlaybackValidationFailure &&
      ApiFailurePresentation.of(error).canRetry;

  Future<void> play(int messageId) async {
    if (_disposed) return;
    if (activeMessageId == messageId &&
        (status == VoiceAnswerPlaybackStatus.loading ||
            status == VoiceAnswerPlaybackStatus.playing)) {
      return;
    }

    final generation = ++_generation;
    _cancelLoad();
    activeMessageId = messageId;
    error = null;
    if (messageId <= 0) {
      status = VoiceAnswerPlaybackStatus.failure;
      error = const VoiceAnswerPlaybackValidationFailure(
        VoiceAnswerPlaybackValidationReason.invalidMessageId,
      );
      notifyListeners();
      await _safeStop();
      return;
    }
    status = VoiceAnswerPlaybackStatus.loading;
    notifyListeners();

    await _safeStop();
    if (!_isCurrent(generation, messageId)) return;

    final cancellation = VoiceAnswerPlaybackCancellation();
    _loadCancellation = cancellation;
    try {
      final audio = await _repository.loadVoiceAnswerAudio(
        messageId,
        cancellation: cancellation,
      );
      if (identical(_loadCancellation, cancellation)) {
        _loadCancellation = null;
      }
      if (!_isCurrent(generation, messageId)) {
        _clearAudio(audio);
        return;
      }
      status = VoiceAnswerPlaybackStatus.playing;
      notifyListeners();

      try {
        await _player.play(audio.bytes, mimeType: audio.mimeType);
      } finally {
        _clearAudio(audio);
      }
      if (!_isCurrent(generation, messageId)) return;
      status = VoiceAnswerPlaybackStatus.completed;
      notifyListeners();
    } on Object catch (caught) {
      if (identical(_loadCancellation, cancellation)) {
        _loadCancellation = null;
      }
      if (!_isCurrent(generation, messageId)) return;
      error = caught;
      status = VoiceAnswerPlaybackStatus.failure;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _generation += 1;
    _cancelLoad();
    if (activeMessageId != null) {
      status = VoiceAnswerPlaybackStatus.stopped;
      error = null;
      notifyListeners();
    }
    await _safeStop();
  }

  /// 활동·대화가 바뀔 때 기존 재생과 화면 상태를 함께 비운다.
  Future<void> reset() async {
    if (_disposed) return;
    _generation += 1;
    _cancelLoad();
    activeMessageId = null;
    status = VoiceAnswerPlaybackStatus.idle;
    error = null;
    notifyListeners();
    await _safeStop();
  }

  bool _isCurrent(int generation, int messageId) =>
      !_disposed && generation == _generation && activeMessageId == messageId;

  void _cancelLoad() {
    final cancellation = _loadCancellation;
    _loadCancellation = null;
    cancellation?.cancel();
  }

  void _clearAudio(VoiceAnswerAudio audio) {
    audio.bytes.fillRange(0, audio.bytes.length, 0);
  }

  Future<void> _safeStop() async {
    try {
      await _player.stop();
    } on Object {
      // stop 실패는 현재 화면 상태를 되돌리지 않는다.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _cancelLoad();
    activeMessageId = null;
    unawaited(_disposePlayer());
    super.dispose();
  }

  Future<void> _disposePlayer() async {
    await _safeStop();
    try {
      await _player.dispose();
    } on Object {
      // 화면 dispose 뒤 player 정리 실패는 UI로 전파하지 않는다.
    }
  }
}
