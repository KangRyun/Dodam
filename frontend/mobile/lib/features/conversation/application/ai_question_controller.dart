import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/models/ai_question.dart';
import '../domain/repositories/conversation_repository.dart';

enum AiQuestionStatus { initial, loading, success, failure }

// 질문 요청과 화면 상태 관리
final class AiQuestionController extends ChangeNotifier {
  AiQuestionController(
    this._repository, {
    required this.conversationId,
    this.basisAnalysisId,
    this.previousAnswerMessageId,
    String Function()? idempotencyKeyProvider,
  }) : _idempotencyKeyProvider = idempotencyKeyProvider ?? _createKey;

  final ConversationRepository _repository;
  final int conversationId;
  final int? basisAnalysisId;
  final int? previousAnswerMessageId;
  final String Function() _idempotencyKeyProvider;

  AiQuestionStatus status = AiQuestionStatus.initial;
  AiQuestion? question;
  Object? error;
  String? _requestKey;
  int? _requestBasisAnalysisId;

  bool get isLoading => status == AiQuestionStatus.loading;

  Future<void> load() => _load(_requestBasisAnalysisId ?? basisAnalysisId);

  /// 새 객체 탐지 결과를 기준으로 다음 질문을 요청한다.
  Future<void> loadForAnalysis(int analysisId) => _load(analysisId);

  Future<void> _load(int? analysisId) async {
    if (analysisId != null && analysisId <= 0) return;
    // 로딩 중 중복 호출과 성공 후 중복 노출 방지
    if (isLoading) return;
    if (status == AiQuestionStatus.success &&
        _requestBasisAnalysisId == analysisId) {
      return;
    }
    // 새 분석 결과는 별도 질문 요청이므로 멱등성 키와 이전 응답을 교체
    if (_requestBasisAnalysisId != analysisId) {
      _requestBasisAnalysisId = analysisId;
      _requestKey = null;
      question = null;
    }
    // 실패 재시도는 같은 요청 키를 재사용
    _requestKey ??= _idempotencyKeyProvider();
    status = AiQuestionStatus.loading;
    error = null;
    notifyListeners();

    try {
      question = await _repository.requestNextQuestion(
        conversationId: conversationId,
        request: NextQuestionRequest(
          basisAnalysisId: analysisId,
          previousAnswerMessageId: previousAnswerMessageId,
        ),
        idempotencyKey: _requestKey!,
      );
      status = AiQuestionStatus.success;
    } catch (caught) {
      error = caught;
      status = AiQuestionStatus.failure;
    }
    notifyListeners();
  }

  static String _createKey() {
    final random = Random.secure();
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'question-$now-${random.nextInt(1 << 32)}';
  }
}
