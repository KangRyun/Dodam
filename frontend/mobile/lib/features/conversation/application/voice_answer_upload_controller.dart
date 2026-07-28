import 'package:flutter/foundation.dart';

import '../../../core/network/network.dart';
import '../domain/models/voice_answer.dart';
import '../domain/models/voice_recording.dart';
import '../domain/repositories/voice_answer_repository.dart';

/// 음성 답변 업로드 상태.
///
/// [consentRequired]는 아동 음성 처리 동의가 없어 서버가 `403 VOICE_CONSENT_REQUIRED`로
/// 거절한 경우다. 재시도해도 같은 결과이므로 [failure]와 구분해 선택형 답변으로 안내한다
/// (API 명세 §12 "음성 처리 동의가 없으면 선택형 답변을 사용한다").
enum VoiceAnswerUploadStatus { idle, uploading, success, failure, consentRequired }

final class VoiceAnswerUploadController extends ChangeNotifier {
  static const _consentRequiredCode = 'VOICE_CONSENT_REQUIRED';

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
    } on ApiResponseFailure catch (failure) {
      // 동의 부재는 재전송으로 해결되지 않으므로 보류 요청을 버리고 별도 상태로 알린다.
      if (failure.error?.code == _consentRequiredCode) {
        status = VoiceAnswerUploadStatus.consentRequired;
        _pendingRequest = null;
        _pendingIdempotencyKey = null;
      } else {
        status = VoiceAnswerUploadStatus.failure;
      }
      notifyListeners();
      return false;
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
