import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/ai_question.dart';
import '../domain/models/question_tts.dart';
import '../domain/repositories/question_tts_repository.dart';
import '../domain/services/question_audio_player.dart';

enum AiQuestionTtsStatus { idle, loading, playing, failure }

final class AiQuestionTtsController extends ChangeNotifier {
  AiQuestionTtsController(
    this._repository,
    this._player, {
    this.request = const QuestionTtsRequest(),
  });

  final QuestionTtsRepository _repository;
  final QuestionAudioPlayer _player;
  final QuestionTtsRequest request;
  final Set<int> _handledMessageIds = <int>{};

  AiQuestionTtsStatus status = AiQuestionTtsStatus.idle;
  Object? error;
  int? _activeMessageId;
  int _generation = 0;
  bool _disposed = false;

  Set<int> get handledMessageIds => Set.unmodifiable(_handledMessageIds);

  Future<void> playQuestion(AiQuestion question) async {
    if (_disposed ||
        !question.ttsAvailable ||
        !_handledMessageIds.add(question.messageId)) {
      return;
    }
    final generation = ++_generation;
    _activeMessageId = question.messageId;
    status = AiQuestionTtsStatus.loading;
    error = null;
    notifyListeners();

    await _safeStop();
    if (!_isCurrent(generation, question.messageId)) return;

    try {
      final audio = await _repository.loadQuestionAudio(
        question.messageId,
        request: request,
      );
      if (!_isCurrent(generation, question.messageId)) return;
      await _player.play(audio.bytes, mimeType: audio.mimeType);
      if (!_isCurrent(generation, question.messageId)) {
        await _safeStop();
        return;
      }
      status = AiQuestionTtsStatus.playing;
    } on Object catch (caught) {
      if (!_isCurrent(generation, question.messageId)) return;
      error = caught;
      status = AiQuestionTtsStatus.failure;
      if (kDebugMode) {
        debugPrint(
          '[AI_QUESTION_TTS] failure exceptionType=${caught.runtimeType}',
        );
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> stop() async {
    if (_disposed) return;
    _generation += 1;
    _activeMessageId = null;
    status = AiQuestionTtsStatus.idle;
    error = null;
    await _safeStop();
    if (!_disposed) notifyListeners();
  }

  bool _isCurrent(int generation, int messageId) =>
      !_disposed && generation == _generation && _activeMessageId == messageId;

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
    await _safeStop();
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
