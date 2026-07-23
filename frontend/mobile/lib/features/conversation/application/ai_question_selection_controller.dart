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
  int? selectedOptionId;
  bool optionsVisible = false;

  void beginQuestion(AiQuestion question, {bool scheduleReveal = true}) {
    if (questionMessageId == question.messageId) return;
    _revealTimer?.cancel();
    questionMessageId = question.messageId;
    selectedOptionId = null;
    optionsVisible = false;
    notifyListeners();
    if (scheduleReveal) {
      _revealTimer = Timer(revealDelay, revealOptions);
    }
  }

  void revealOptions() {
    if (optionsVisible) return;
    optionsVisible = true;
    notifyListeners();
  }

  void hideOptions() {
    _revealTimer?.cancel();
    if (!optionsVisible) return;
    optionsVisible = false;
    notifyListeners();
  }

  bool select(AiQuestion question, int optionId) {
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
