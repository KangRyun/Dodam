import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/ai_question.dart';
import '../domain/models/question_tts.dart';
import '../domain/repositories/question_tts_repository.dart';
import '../domain/services/question_audio_player.dart';
import '../domain/services/question_speech_synthesizer.dart';

enum AiQuestionTtsStatus { idle, loading, playing, failure }

/// 질문 음성 재생을 서버 → 재시도 → 기기 음성 → 수동 재생 순서로 이어 붙인다 (P0-3).
///
/// 예전에는 [playQuestion]이 messageId 당 **딱 한 번만** 시도했다. 서버가 한 번 실패하면
/// 그 질문은 영영 소리가 나지 않았고, 재생 버튼을 눌러도 같은 가드에 막혀 아무 일도 일어나지
/// 않았다(2026-08-08 실측: 5문항 전부 무음). 자동 재생은 여전히 한 번이지만, 그 가드는
/// [replayQuestion]을 막지 않는다.
final class AiQuestionTtsController extends ChangeNotifier {
  AiQuestionTtsController(
    this._repository,
    this._player, {
    this.request = const QuestionTtsRequest(),
    this.synthesizer = const NoopQuestionSpeechSynthesizer(),
    this.retryDelay = const Duration(milliseconds: 400),
  });

  final QuestionTtsRepository _repository;
  final QuestionAudioPlayer _player;
  final QuestionSpeechSynthesizer synthesizer;
  final QuestionTtsRequest request;

  /// 서버 재시도까지의 간격이다. 짧게 둔다 — 아이가 질문을 기다리는 시간이다.
  final Duration retryDelay;

  final Set<int> _autoPlayedMessageIds = <int>{};

  AiQuestionTtsStatus status = AiQuestionTtsStatus.idle;
  Object? error;

  /// 마지막 재생이 기기 음성으로 대체됐으면 `true`다.
  ///
  /// 캐릭터 목소리가 아니라는 것을 화면이 알 수 있어야, 다시 듣기를 권할지 판단할 수 있다.
  bool usedDeviceFallback = false;

  int? _activeMessageId;
  int _generation = 0;
  bool _disposed = false;

  Set<int> get handledMessageIds => Set.unmodifiable(_autoPlayedMessageIds);

  /// 소리가 나지 않은 질문이라 수동 재생 버튼을 보여야 하면 `true`다.
  bool get needsManualReplay => status == AiQuestionTtsStatus.failure;

  /// 질문이 열릴 때 한 번 자동으로 읽어 준다.
  ///
  /// 같은 질문에 두 번 자동 재생하지 않는다 — 화면이 다시 그려질 때마다 소리가 겹친다.
  Future<void> playQuestion(
    AiQuestion question, {
    QuestionTtsToneProfile toneProfile =
        QuestionTtsToneProfile.characterDefault,
  }) async {
    if (_disposed ||
        !question.ttsAvailable ||
        !_autoPlayedMessageIds.add(question.messageId)) {
      return;
    }
    await _speak(question, toneProfile);
  }

  /// 아이나 보호자가 재생 버튼을 눌렀을 때 다시 읽어 준다.
  ///
  /// 자동 재생 가드를 지나친다. 이것이 P0-3의 마지막 안전망이다 — 서버도 기기 음성도 안 될 때
  /// 남는 유일한 길이 사람이 직접 누르는 것이다.
  Future<void> replayQuestion(
    AiQuestion question, {
    QuestionTtsToneProfile toneProfile =
        QuestionTtsToneProfile.characterDefault,
  }) async {
    if (_disposed || !question.ttsAvailable) return;
    _autoPlayedMessageIds.add(question.messageId);
    await _speak(question, toneProfile);
  }

  Future<void> _speak(
    AiQuestion question,
    QuestionTtsToneProfile toneProfile,
  ) async {
    final generation = ++_generation;
    _activeMessageId = question.messageId;
    status = AiQuestionTtsStatus.loading;
    error = null;
    usedDeviceFallback = false;
    notifyListeners();

    await _stopEverything();
    if (!_isCurrent(generation, question.messageId)) return;

    // 1) 서버 TTS. 2) 짧은 재시도 — 순간적인 네트워크·게이트웨이 흔들림이 대부분이다.
    for (var attempt = 0; attempt < 2; attempt += 1) {
      if (attempt > 0) {
        await Future<void>.delayed(retryDelay);
        if (!_isCurrent(generation, question.messageId)) return;
      }
      final played = await _playFromServer(question, toneProfile, generation);
      if (played == null) return; // 다른 질문으로 넘어갔다.
      if (played) {
        status = AiQuestionTtsStatus.playing;
        if (!_disposed) notifyListeners();
        return;
      }
    }

    // 3) 기기 음성. 캐릭터 목소리는 아니지만 질문은 들린다.
    final spoken = await _speakOnDevice(question.text);
    if (!_isCurrent(generation, question.messageId)) return;
    if (spoken) {
      usedDeviceFallback = true;
      status = AiQuestionTtsStatus.playing;
      if (!_disposed) notifyListeners();
      return;
    }

    // 4) 수동 재생 버튼만 남는다. 여기서도 보기 선택·건너뛰기는 막지 않는다.
    status = AiQuestionTtsStatus.failure;
    if (!_disposed) notifyListeners();
  }

  /// @return 재생했으면 `true`, 실패했으면 `false`, 대상이 바뀌었으면 `null`
  Future<bool?> _playFromServer(
    AiQuestion question,
    QuestionTtsToneProfile toneProfile,
    int generation,
  ) async {
    try {
      final audio = await _repository.loadQuestionAudio(
        question.messageId,
        request: request.copyWith(toneProfile: toneProfile),
      );
      if (!_isCurrent(generation, question.messageId)) return null;
      await _player.play(audio.bytes, mimeType: audio.mimeType);
      if (!_isCurrent(generation, question.messageId)) {
        await _safeStop();
        return null;
      }
      return true;
    } on Object catch (caught) {
      if (!_isCurrent(generation, question.messageId)) return null;
      error = caught;
      if (kDebugMode) {
        // ⚠️ 예외 원문을 찍지 않는다. 응답 본문에 서명된 URL이 섞여 들어올 수 있다.
        debugPrint(
          '[AI_QUESTION_TTS] server_failure exceptionType=${caught.runtimeType}',
        );
      }
      return false;
    }
  }

  Future<bool> _speakOnDevice(String text) async {
    try {
      return await synthesizer.speak(text);
    } on Object catch (caught) {
      if (kDebugMode) {
        debugPrint(
          '[AI_QUESTION_TTS] fallback_failure exceptionType=${caught.runtimeType}',
        );
      }
      return false;
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _generation += 1;
    _activeMessageId = null;
    status = AiQuestionTtsStatus.idle;
    error = null;
    usedDeviceFallback = false;
    await _stopEverything();
    if (!_disposed) notifyListeners();
  }

  bool _isCurrent(int generation, int messageId) =>
      !_disposed && generation == _generation && _activeMessageId == messageId;

  Future<void> _stopEverything() async {
    await _safeStop();
    try {
      await synthesizer.stop();
    } on Object catch (caught) {
      if (kDebugMode) {
        debugPrint(
          '[AI_QUESTION_TTS] fallback_stop_failure exceptionType=${caught.runtimeType}',
        );
      }
    }
  }

  Future<void> _safeStop() async {
    try {
      await _player.stop();
    } on Object catch (caught) {
      if (kDebugMode) {
        debugPrint(
          '[AI_QUESTION_TTS] stop_failure exceptionType=${caught.runtimeType}',
        );
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _activeMessageId = null;
    unawaited(_disposePlayer());
    super.dispose();
  }

  Future<void> _disposePlayer() async {
    await _stopEverything();
    try {
      await _player.dispose();
    } on Object catch (caught) {
      if (kDebugMode) {
        debugPrint(
          '[AI_QUESTION_TTS] dispose_failure exceptionType=${caught.runtimeType}',
        );
      }
    }
  }
}
