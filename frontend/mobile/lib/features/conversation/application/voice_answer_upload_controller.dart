import 'package:flutter/foundation.dart';

import '../domain/models/voice_answer.dart';
import '../domain/models/voice_recording.dart';
import '../domain/repositories/voice_answer_repository.dart';

enum VoiceAnswerUploadStatus { idle, uploading, success, failure }

final class VoiceAnswerUploadController extends ChangeNotifier {
  VoiceAnswerUploadController(
    this._repository, {
    required this.conversationId,
    required this.idempotencyKeyProvider,
  });

  final VoiceAnswerRepository _repository;
  final int conversationId;
  final String Function() idempotencyKeyProvider;

  VoiceAnswerUploadStatus status = VoiceAnswerUploadStatus.idle;
  VoiceAnswerUploadResult? result;
  VoiceAnswerUploadRequest? _pendingRequest;
  String? _pendingIdempotencyKey;

  Future<bool> submit({
    required int questionMessageId,
    required VoiceRecording recording,
  }) async {
    if (status == VoiceAnswerUploadStatus.uploading) return false;
    _pendingRequest ??= VoiceAnswerUploadRequest(
      questionMessageId: questionMessageId,
      recording: recording,
    );
    _pendingIdempotencyKey ??= idempotencyKeyProvider();
    status = VoiceAnswerUploadStatus.uploading;
    notifyListeners();
    try {
      result = await _repository.upload(
        conversationId: conversationId,
        request: _pendingRequest!,
        idempotencyKey: _pendingIdempotencyKey!,
      );
      status = VoiceAnswerUploadStatus.success;
      _pendingRequest = null;
      _pendingIdempotencyKey = null;
      notifyListeners();
      return true;
    } catch (_) {
      status = VoiceAnswerUploadStatus.failure;
      notifyListeners();
      return false;
    }
  }

  Future<bool> retry() async {
    final request = _pendingRequest;
    if (request == null) return false;
    return submit(
      questionMessageId: request.questionMessageId,
      recording: request.recording,
    );
  }

  void beginQuestion() {
    status = VoiceAnswerUploadStatus.idle;
    result = null;
    _pendingRequest = null;
    _pendingIdempotencyKey = null;
    notifyListeners();
  }
}
