import 'package:flutter/foundation.dart';

/// 한 질문의 답변 진행 단계.
///
/// 순서가 곧 규칙이다 — 질문을 받고, 들려주고, 답할 수 있게 되고, 한 가지 수단으로
/// 답하고, 끝난다. 이 순서를 코드가 강제하지 않으면 여러 수단이 동시에 답을 만든다.
enum AnswerFlowStage {
  /// 질문을 받아오는 중이다.
  questionLoading,

  /// 질문 음성을 들려주는 중이다. **이 동안 녹음을 시작하지 않는다.**
  ttsPlaying,

  /// 아이가 답할 수 있다. 아직 아무 수단도 시작하지 않았다.
  answerReady,

  /// 음성으로 답하는 중이다.
  voiceRecording,

  /// 보기에서 고른 답을 보내는 중이다.
  optionSubmitting,

  /// 건너뛰기를 보내는 중이다.
  skipSubmitting,

  /// 이 질문의 답이 확정됐다. **더 이상 어떤 수단도 답을 만들 수 없다.**
  answerSubmitted,
}

/// 답을 만든 수단.
enum AnswerSource {
  /// 아이가 말한 음성.
  voice,

  /// 아이가 고른 보기.
  option,

  /// 건너뛰기.
  skip,
}

/// 한 질문에 답이 하나만 남게 하는 상태 머신.
///
/// 이 컨트롤러가 없을 때 실제로 일어난 일이다. 질문이 뜨면 자동 녹음이 시작되고,
/// 아이가 보기를 누르는 사이 무음 녹음이 먼저 답으로 올라갔다. 아이가 고른 답은
/// 두 번째 답이 되거나 버려졌다 — **아이가 실제로 고른 것이 기록에서 사라졌다.**
///
/// 그래서 규칙은 하나다. **한 messageId에서 답을 만들 수 있는 수단은 먼저 잡은
/// 하나뿐이다.** 늦게 도착한 recorder callback, 두 번 눌린 보기, 건너뛰기 중에
/// 끝난 녹음은 전부 잡지 못하고 무시된다.
///
/// 예외가 하나 있다. **아이가 고른 답은 자동 무음 녹음을 이긴다** — 자동 녹음은
/// 아이가 시작한 것이 아니라 앱이 시작한 것이라, 아이의 선택보다 앞설 수 없다.
final class AnswerFlowController extends ChangeNotifier {
  /// 답변 흐름 컨트롤러를 만든다.
  AnswerFlowController();

  AnswerFlowStage _stage = AnswerFlowStage.questionLoading;
  int? _messageId;
  AnswerSource? _claimedBy;
  bool _voiceStartedAutomatically = false;

  /// 현재 단계.
  AnswerFlowStage get stage => _stage;

  /// 현재 질문 식별자이며 아직 질문이 없으면 `null`.
  int? get messageId => _messageId;

  /// 답을 만든(만들고 있는) 수단이며 아직 없으면 `null`.
  AnswerSource? get claimedBy => _claimedBy;

  /// 질문 음성을 들려주는 중인지.
  bool get isTtsPlaying => _stage == AnswerFlowStage.ttsPlaying;

  /// 음성 녹음 중인지.
  ///
  /// **재생 중과 동시에 참이 될 수 없다** — 두 단계가 배타적인 enum 값이라
  /// 상태 자체로 불가능하다.
  bool get isVoiceRecording => _stage == AnswerFlowStage.voiceRecording;

  /// 답이 확정됐는지.
  bool get isSubmitted => _stage == AnswerFlowStage.answerSubmitted;

  /// 아이가 답할 수단을 고를 수 있는지.
  bool get canChooseAnswer =>
      _stage == AnswerFlowStage.answerReady ||
      _stage == AnswerFlowStage.voiceRecording;

  /// 자동 녹음을 시작해도 되는지.
  ///
  /// **TTS가 끝나야 한다.** 재생 중에 녹음을 켜면 질문 소리가 그대로 답으로 녹음되고,
  /// 아이는 질문을 다 듣기도 전에 답해야 한다.
  bool get canStartAutomaticVoice => _stage == AnswerFlowStage.answerReady;

  /// 새 질문을 받기 시작한다. 이전 질문의 상태는 여기서 전부 버린다.
  ///
  /// @param messageId 새 질문 식별자
  void beginQuestion(int messageId) {
    _messageId = messageId;
    _stage = AnswerFlowStage.questionLoading;
    _claimedBy = null;
    _voiceStartedAutomatically = false;
    notifyListeners();
  }

  /// 질문 음성 재생을 시작한다.
  void beginTts() {
    if (_stage != AnswerFlowStage.questionLoading) return;
    _stage = AnswerFlowStage.ttsPlaying;
    notifyListeners();
  }

  /// 질문 음성 재생이 끝났다(성공·실패·건너뜀 모두).
  ///
  /// **실패해도 여기로 온다.** TTS가 안 된다고 아이가 답할 수 없으면 대화가 멈춘다.
  void markAnswerReady() {
    if (_stage != AnswerFlowStage.questionLoading &&
        _stage != AnswerFlowStage.ttsPlaying) {
      return;
    }
    _stage = AnswerFlowStage.answerReady;
    notifyListeners();
  }

  /// 음성 녹음 시작을 잡는다.
  ///
  /// @param automatic 앱이 자동으로 시작한 녹음이면 `true`
  /// @return 잡았으면 `true`. 이미 다른 수단이 잡았으면 `false`
  bool claimVoice({required bool automatic}) {
    if (_stage != AnswerFlowStage.answerReady) return false;
    _stage = AnswerFlowStage.voiceRecording;
    _claimedBy = AnswerSource.voice;
    _voiceStartedAutomatically = automatic;
    notifyListeners();
    return true;
  }

  /// 보기 선택을 잡는다.
  ///
  /// **진행 중인 자동 녹음을 밀어낸다.** 아이가 고른 답이 앱이 켠 녹음보다 앞선다.
  /// 아이가 직접 시작한 녹음(수동)은 밀어내지 않는다 — 그건 아이의 답이다.
  ///
  /// @return 잡았으면 `true`. 이미 답이 확정됐거나 다른 수단이 진행 중이면 `false`
  bool claimOption() => _claimUserAnswer(AnswerSource.option);

  /// 건너뛰기를 잡는다.
  ///
  /// @return 잡았으면 `true`
  bool claimSkip() => _claimUserAnswer(AnswerSource.skip);

  bool _claimUserAnswer(AnswerSource source) {
    if (_stage == AnswerFlowStage.answerSubmitted) return false;
    if (_stage == AnswerFlowStage.optionSubmitting ||
        _stage == AnswerFlowStage.skipSubmitting) {
      // 두 번 눌렸다. 먼저 잡은 요청이 이미 가고 있다.
      return false;
    }
    if (_stage == AnswerFlowStage.voiceRecording && !_voiceStartedAutomatically) {
      // 아이가 직접 시작한 녹음은 아이의 답이라 보기가 가로채지 않는다.
      return false;
    }
    if (_stage == AnswerFlowStage.questionLoading ||
        _stage == AnswerFlowStage.ttsPlaying) {
      // 질문을 다 들려주기 전에도 아이가 보기를 누를 수 있다. 막지 않는다 —
      //   막으면 TTS가 실패해 재생이 끝나지 않을 때 대화가 멈춘다.
      _stage = AnswerFlowStage.answerReady;
    }
    _stage = source == AnswerSource.option
        ? AnswerFlowStage.optionSubmitting
        : AnswerFlowStage.skipSubmitting;
    _claimedBy = source;
    _voiceStartedAutomatically = false;
    notifyListeners();
    return true;
  }

  /// 이 수단이 지금 답을 만들 자격이 있는지.
  ///
  /// 늦게 도착한 recorder callback을 거르는 자리다. 녹음이 끝났다는 소식이
  /// 보기 선택 뒤에 도착하면 여기서 걸린다.
  ///
  /// @param source 확인할 수단
  /// @param messageId 그 결과가 속한 질문이며 다르면 다른 질문의 결과다
  /// @return 답을 만들어도 되면 `true`
  bool canSubmit(AnswerSource source, {required int messageId}) =>
      _messageId == messageId &&
      _claimedBy == source &&
      _stage != AnswerFlowStage.answerSubmitted;

  /// 답을 확정한다. 잡지 못한 수단의 확정 요청은 무시한다.
  ///
  /// @param source 답을 만든 수단
  /// @param messageId 그 답이 속한 질문
  /// @return 확정했으면 `true`
  bool markSubmitted(AnswerSource source, {required int messageId}) {
    if (!canSubmit(source, messageId: messageId)) return false;
    _stage = AnswerFlowStage.answerSubmitted;
    notifyListeners();
    return true;
  }

  /// 잡았던 수단을 놓는다(녹음 취소·전송 실패). 답은 확정되지 않는다.
  ///
  /// @param source 놓을 수단
  void release(AnswerSource source) {
    if (_stage == AnswerFlowStage.answerSubmitted) return;
    if (_claimedBy != source) return;
    _claimedBy = null;
    _voiceStartedAutomatically = false;
    _stage = AnswerFlowStage.answerReady;
    notifyListeners();
  }
}
