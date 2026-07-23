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

  bool get isLoading => status == AiQuestionStatus.loading;

  Future<void> load() async {
    // 로딩 중 중복 호출과 성공 후 중복 노출 방지
    if (isLoading || status == AiQuestionStatus.success) return;
    // 실패 재시도는 같은 요청 키를 재사용
    _requestKey ??= _idempotencyKeyProvider();
    status = AiQuestionStatus.loading;
    error = null;
    notifyListeners();

    try {
      question = await _repository.requestNextQuestion(
        conversationId: conversationId,
        request: NextQuestionRequest(
          basisAnalysisId: basisAnalysisId,
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
