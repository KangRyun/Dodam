import 'package:flutter/foundation.dart';

import '../../../core/network/network.dart';
import '../domain/models/voice_answer.dart';
import '../domain/models/voice_recording.dart';
import '../domain/repositories/voice_answer_repository.dart';
import 'conversation_retry_policy.dart';

/// 음성 답변 업로드 상태.
///
/// [consentRequired]는 아동 음성 처리 동의가 없어 서버가 `403 VOICE_CONSENT_REQUIRED`로
/// 거절한 경우다. 재시도해도 같은 결과이므로 [failure]와 구분해 선택형 답변으로 안내한다
/// (API 명세 §12 "음성 처리 동의가 없으면 선택형 답변을 사용한다").
enum VoiceAnswerUploadStatus {
  idle,
  uploading,
  success,
  failure,
  consentRequired,
}

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
  Object? error;

  /// 보류 중인 업로드. 파일·질문 ID·Key를 한 묶음으로 들고 있어야 재전송이
  /// 같은 fingerprint로 나간다.
  VoiceAnswerUploadRequest? _pendingRequest;
  String? _pendingIdempotencyKey;
  int _generation = 0;
  int? _questionMessageId;
  bool _disposed = false;

  /// 재시도 조작을 노출해도 되는 실패인지.
  ///
  /// 동의 필요는 전용 안내로 처리하므로 여기서 재시도를 제공하지 않는다.
  bool get canRetry =>
      status == VoiceAnswerUploadStatus.failure &&
      _pendingRequest != null &&
      canRetryConversationRequest(
        error,
        endpoint: ConversationRequestEndpoint.voiceAnswer,
      );

  Future<bool> submit({
    required int questionMessageId,
    required VoiceRecording recording,
  }) async {
    if (_disposed || status == VoiceAnswerUploadStatus.uploading) return false;
    if (status == VoiceAnswerUploadStatus.failure &&
        blocksConversationAction(error)) {
      return false;
    }
    // 다른 질문의 보류 요청을 물려받지 않는다 — Body가 달라져 Key가 재사용된다.
    if (_pendingRequest?.questionMessageId != questionMessageId) {
      _pendingRequest = null;
      _pendingIdempotencyKey = null;
    }
    final request = _pendingRequest ??= VoiceAnswerUploadRequest(
      questionMessageId: questionMessageId,
      recording: recording,
    );
    final key = _pendingIdempotencyKey ??= idempotencyKeyProvider();
    _questionMessageId = questionMessageId;
    final generation = _generation;

    status = VoiceAnswerUploadStatus.uploading;
    error = null;
    notifyListeners();
    try {
      final uploaded = await _repository.upload(
        conversationId: conversationId,
        request: request,
        idempotencyKey: key,
      );
      if (!_isCurrent(generation, questionMessageId)) return false;
      result = uploaded;
      status = VoiceAnswerUploadStatus.success;
      _pendingRequest = null;
      _pendingIdempotencyKey = null;
      notifyListeners();
      return true;
    } on ApiResponseFailure catch (failure) {
      if (!_isCurrent(generation, questionMessageId)) return false;
      error = failure;
      // 동의 부재는 재전송으로 해결되지 않으므로 보류 요청을 버리고 별도 상태로 알린다.
      if (failure.error?.code == _consentRequiredCode) {
        status = VoiceAnswerUploadStatus.consentRequired;
        _pendingRequest = null;
        _pendingIdempotencyKey = null;
      } else {
        status = VoiceAnswerUploadStatus.failure;
        // 저장 전 거절이 확정된 실패는 같은 Key 재전송이 무의미하다.
        if (!shouldKeepRequestSnapshot(
          failure,
          endpoint: ConversationRequestEndpoint.voiceAnswer,
        )) {
          _pendingRequest = null;
          _pendingIdempotencyKey = null;
        }
      }
      notifyListeners();
      return false;
    } catch (caught) {
      if (!_isCurrent(generation, questionMessageId)) return false;
      error = caught;
      status = VoiceAnswerUploadStatus.failure;
      if (!shouldKeepRequestSnapshot(
        caught,
        endpoint: ConversationRequestEndpoint.voiceAnswer,
      )) {
        _pendingRequest = null;
        _pendingIdempotencyKey = null;
      }
      notifyListeners();
      return false;
    }
  }

  Future<bool> retry() async {
    final request = _pendingRequest;
    if (_disposed || request == null) return false;
    return submit(
      questionMessageId: request.questionMessageId,
      recording: request.recording,
    );
  }

  /// 새 질문으로 넘어가며 이전 질문의 업로드를 모두 무효화한다.
  void beginQuestion(int questionMessageId) {
    if (_disposed) return;
    _generation += 1;
    _questionMessageId = questionMessageId;
    status = VoiceAnswerUploadStatus.idle;
    result = null;
    error = null;
    _pendingRequest = null;
    _pendingIdempotencyKey = null;
    notifyListeners();
  }

  bool _isCurrent(int generation, int questionMessageId) =>
      !_disposed &&
      generation == _generation &&
      questionMessageId == _questionMessageId;

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
