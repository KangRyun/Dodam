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

  /// 이미 받은 질문을 다시 보이게 한다.
  ///
  /// [receive]는 같은 messageId를 두 번 받지 않는다(중복 노출 방지). 음성 답변이
  /// 무음·거절로 무효가 되면 그 질문은 아직 답을 못 받은 상태이므로, 새 질문을 만들지
  /// 않고 표시만 되살려 선택지로 답할 기회를 준다.
  void restore() {
    if (visibleQuestion == null || isVisible) return;
    isVisible = true;
    notifyListeners();
  }
}
