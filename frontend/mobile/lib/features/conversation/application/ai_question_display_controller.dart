import 'package:flutter/foundation.dart';

import '../domain/models/ai_question.dart';

// 새 질문 자동 표시와 messageId 기반 중복 노출 관리
final class AiQuestionDisplayController extends ChangeNotifier {
  final Set<int> _displayedMessageIds = <int>{};

  AiQuestion? visibleQuestion;
  bool isVisible = false;

  Set<int> get displayedMessageIds => Set.unmodifiable(_displayedMessageIds);

  bool receive(AiQuestion question) {
    // 같은 문장이어도 messageId가 다르면 별도 질문으로 처리
    if (!_displayedMessageIds.add(question.messageId)) return false;
    visibleQuestion = question;
    isVisible = true;
    notifyListeners();
    return true;
  }

  void dismiss() {
    if (!isVisible) return;
    isVisible = false;
    notifyListeners();
  }
}
