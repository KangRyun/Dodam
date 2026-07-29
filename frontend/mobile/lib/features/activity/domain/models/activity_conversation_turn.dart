import '../../data/dto/activity_dtos.dart';

/// 화면에 보여줄 한 묶음 — AI 질문 하나와 그 질문에 달린 아동 답변들.
///
/// 백엔드는 메시지를 평면 목록으로 주고 답변은 `parentMessageId`로 질문을
/// 가리킨다. 화면이 그 연결을 매번 다시 계산하지 않도록 여기서 한 번만
/// 정리한다.
///
/// 질문을 찾지 못한 아동 답변은 [question]이 null인 묶음으로 남긴다.
/// 보호자 상세 화면의 질문·답변 계약에 해당하지 않는 시스템 메시지와 알 수
/// 없는 메시지는 제외해 다른 메시지의 표시를 방해하지 않게 한다.
final class ActivityConversationTurn {
  const ActivityConversationTurn({this.question, this.answers = const []});

  final ActivityConversationMessageDto? question;
  final List<ActivityConversationMessageDto> answers;

  /// 답변이 하나도 없는 질문인지(건너뛴 질문 포함).
  bool get hasNoAnswer => answers.isEmpty;

  /// 메시지 목록을 순번 오름차순 질문·답변 묶음으로 정리한다.
  ///
  /// 같은 `messageId`가 여러 페이지에 걸쳐 두 번 와도 한 번만 쓰고, 순번이
  /// 뒤섞여 와도 `sequence` 오름차순(같으면 `messageId` 순)으로 세운다.
  static List<ActivityConversationTurn> group(
    Iterable<ActivityConversationMessageDto> messages,
  ) {
    final turns = <_Turn>[];
    final turnByQuestionId = <int, _Turn>{};
    for (final message in order(messages)) {
      if (_isAiQuestion(message)) {
        final turn = _Turn(message);
        turns.add(turn);
        turnByQuestionId[message.messageId] = turn;
        continue;
      }
      if (!_isChildAnswer(message)) continue;

      final parent = switch (message.parentMessageId) {
        final parentId? => turnByQuestionId[parentId],
        _ => null,
      };
      if (parent == null) {
        turns.add(_Turn(null)..answers.add(message));
      } else {
        parent.answers.add(message);
      }
    }
    return [
      for (final turn in turns)
        ActivityConversationTurn(
          question: turn.question,
          answers: List.unmodifiable(turn.answers),
        ),
    ];
  }

  static bool _isAiQuestion(ActivityConversationMessageDto message) =>
      message.senderType == 'AI' && message.messageType == 'QUESTION';

  static bool _isChildAnswer(ActivityConversationMessageDto message) =>
      message.senderType == 'CHILD' &&
      const {
        'ANSWER_OPTION',
        'ANSWER_VOICE',
        'ANSWER_TEXT',
      }.contains(message.messageType);

  /// 중복 `messageId`를 걸러 순번 오름차순으로 세운다.
  static List<ActivityConversationMessageDto> order(
    Iterable<ActivityConversationMessageDto> messages,
  ) {
    final unique = <int, ActivityConversationMessageDto>{};
    for (final message in messages) {
      unique.putIfAbsent(message.messageId, () => message);
    }
    return unique.values.toList(growable: false)..sort((a, b) {
      final bySequence = a.sequence.compareTo(b.sequence);
      return bySequence != 0 ? bySequence : a.messageId.compareTo(b.messageId);
    });
  }
}

final class _Turn {
  _Turn(this.question);
  final ActivityConversationMessageDto? question;
  final List<ActivityConversationMessageDto> answers = [];
}
