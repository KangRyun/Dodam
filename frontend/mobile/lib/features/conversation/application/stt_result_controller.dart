import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/stt_result.dart';
import '../domain/repositories/stt_result_repository.dart';

enum SttResultStatus { idle, polling, success, failure, delayed }

final class SttResultController extends ChangeNotifier {
  SttResultController(
    this._repository, {
    required this.conversationId,
    this.pollInterval = const Duration(seconds: 1),
    this.maxAttempts = 15,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final SttResultRepository _repository;
  final int conversationId;
  final Duration pollInterval;
  final int maxAttempts;
  final Future<void> Function(Duration) _delay;

  SttResultStatus status = SttResultStatus.idle;
  String? text;
  int? messageId;
  int _generation = 0;

  Future<void> watch({required int messageId, required int sequence}) async {
    final generation = ++_generation;
    status = SttResultStatus.polling;
    text = null;
    this.messageId = messageId;
    notifyListeners();
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (generation != _generation) return;
      try {
        final result = await _repository.getResult(
          conversationId: conversationId,
          messageId: messageId,
          afterSequence: sequence - 1,
        );
        if (result.status == SttSpeechStatus.success &&
            result.text?.trim().isNotEmpty == true) {
          status = SttResultStatus.success;
          text = result.text!.trim();
          notifyListeners();
          return;
        }
        if (result.status == SttSpeechStatus.failed) {
          status = SttResultStatus.failure;
          notifyListeners();
          return;
        }
      } catch (_) {
        if (attempt == maxAttempts - 1) {
          status = SttResultStatus.failure;
          notifyListeners();
          return;
        }
      }
      await _delay(pollInterval);
    }
    if (generation == _generation) {
      status = SttResultStatus.delayed;
      notifyListeners();
    }
  }

  void dismiss() {
    _generation++;
    status = SttResultStatus.idle;
    text = null;
    messageId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
