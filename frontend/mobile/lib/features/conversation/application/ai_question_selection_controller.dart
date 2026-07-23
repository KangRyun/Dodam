import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/ai_question.dart';

// 질문별 선택지 선택 상태 관리
final class AiQuestionSelectionController extends ChangeNotifier {
  AiQuestionSelectionController({
    this.revealDelay = const Duration(milliseconds: 2500),
  });

  final Duration revealDelay;
  Timer? _revealTimer;
  int? questionMessageId;
  String? selectedOptionId;
  bool optionsVisible = false;

  void beginQuestion(AiQuestion question) {
    if (questionMessageId == question.messageId) return;
    _revealTimer?.cancel();
    questionMessageId = question.messageId;
    selectedOptionId = null;
    optionsVisible = false;
    notifyListeners();
    _revealTimer = Timer(revealDelay, () {
      optionsVisible = true;
      notifyListeners();
    });
  }

  bool select(AiQuestion question, String optionId) {
    final validOption = question.options.any(
      (option) => option.optionId == optionId,
    );
    if (!validOption) return false;
    if (questionMessageId != question.messageId) beginQuestion(question);
    if (selectedOptionId == optionId) return true;
    selectedOptionId = optionId;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }
}
