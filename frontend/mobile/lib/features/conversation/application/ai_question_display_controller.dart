import 'package:flutter/foundation.dart';

import '../domain/models/ai_question.dart';

// 새 질문 자동 표시와 messageId 기반 중복 노출 관리
final class AiQuestionDisplayController extends ChangeNotifier {
  final Set<int> _displayedMessageIds = <int>{};
  bool _conversationCleared = false;

  AiQuestion? visibleQuestion;
  bool isVisible = false;

  Set<int> get displayedMessageIds => Set.unmodifiable(_displayedMessageIds);
  bool get hasUnresolvedQuestion => isVisible && visibleQuestion != null;

  bool receive(AiQuestion question) {
    if (_conversationCleared) return false;
    // 같은 문장이어도 messageId가 다르면 별도 질문으로 처리
    if (!_displayedMessageIds.add(question.messageId)) return false;
    visibleQuestion = question;
    isVisible = true;
    notifyListeners();
    return true;
  }

  bool resolveQuestion(int messageId) {
    if (!hasUnresolvedQuestion || visibleQuestion!.messageId != messageId) {
      return false;
    }
    _clearVisibleQuestion();
    return true;
  }

  void clearConversation() {
    _conversationCleared = true;
    _clearVisibleQuestion();
  }

  void dismiss() {
    if (!isVisible) return;
    isVisible = false;
    notifyListeners();
  }

  void _clearVisibleQuestion() {
    if (!isVisible && visibleQuestion == null) return;
    visibleQuestion = null;
    isVisible = false;
    notifyListeners();
  }
}
