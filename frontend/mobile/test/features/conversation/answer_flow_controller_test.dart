import 'package:dodam/features/conversation/application/answer_flow_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 한 질문에 답이 하나만 남게 하는 상태 머신.
///
/// 이 테스트가 막는 실패는 하나다 — **아이가 고른 답이 앱이 켠 녹음에 덮이는 것.**
/// 2026-08-08 태블릿 실행에서 그 일이 났다: 질문마다 자동 녹음이 시작되고, 무음
/// 녹음이 답으로 올라간 뒤에야 보기가 다시 떴다.
void main() {
  group('자동 녹음과 보기 선택', () {
    test('1. 자동 녹음 중 보기를 고르면 보기가 이긴다', () {
      final flow = _readyFlow();
      expect(flow.claimVoice(automatic: true), isTrue);
      expect(flow.isVoiceRecording, isTrue);

      // 앱이 켠 녹음은 아이의 답보다 앞설 수 없다.
      expect(flow.claimOption(), isTrue);
      expect(flow.stage, AnswerFlowStage.optionSubmitting);
      expect(flow.claimedBy, AnswerSource.option);
      // 밀려난 녹음은 더 이상 답을 만들 수 없다.
      expect(flow.canSubmit(AnswerSource.voice, messageId: 10), isFalse);
    });

    test('2. 무음 timeout 직전 보기를 골라도 녹음이 답을 만들지 못한다', () {
      final flow = _readyFlow();
      flow.claimVoice(automatic: true);
      flow.claimOption();

      // timeout 이 그 직후 도착한다 — 이미 보기가 잡았다.
      expect(flow.markSubmitted(AnswerSource.voice, messageId: 10), isFalse);
      expect(flow.markSubmitted(AnswerSource.option, messageId: 10), isTrue);
      expect(flow.isSubmitted, isTrue);
    });

    test('3. 녹음 완료 callback 직후 보기를 골라도 답이 두 번 남지 않는다', () {
      final flow = _readyFlow();
      flow.claimVoice(automatic: true);
      // 녹음이 먼저 확정됐다.
      expect(flow.markSubmitted(AnswerSource.voice, messageId: 10), isTrue);

      // 확정 뒤에는 어떤 수단도 답을 만들 수 없다.
      expect(flow.claimOption(), isFalse);
      expect(flow.markSubmitted(AnswerSource.option, messageId: 10), isFalse);
    });

    test('4. 보기를 두 번 눌러도 한 번만 나간다', () {
      final flow = _readyFlow();

      expect(flow.claimOption(), isTrue);
      expect(flow.claimOption(), isFalse, reason: '두 번째 탭은 잡지 못한다');
    });

    test('5. 지난 질문의 recorder callback 은 무시한다', () {
      final flow = _readyFlow();
      flow.claimVoice(automatic: true);

      // 다음 질문으로 넘어간 뒤 이전 질문의 녹음이 끝났다고 알려 온다.
      flow.beginQuestion(11);
      expect(flow.canSubmit(AnswerSource.voice, messageId: 10), isFalse);
      expect(flow.markSubmitted(AnswerSource.voice, messageId: 10), isFalse);
    });

    test('6. 건너뛰기 중 녹음이 끝나도 건너뛰기가 유지된다', () {
      final flow = _readyFlow();
      flow.claimVoice(automatic: true);

      expect(flow.claimSkip(), isTrue);
      expect(flow.stage, AnswerFlowStage.skipSubmitting);
      expect(flow.markSubmitted(AnswerSource.voice, messageId: 10), isFalse);
      expect(flow.markSubmitted(AnswerSource.skip, messageId: 10), isTrue);
    });

    test('7. TTS 실패로 재생이 끝나지 않아도 보기를 고를 수 있다', () {
      // TTS 가 안 된다고 대화가 멈추면, 글 못 읽는 아이는 아무것도 할 수 없다.
      final flow = AnswerFlowController()..beginQuestion(10);
      flow.beginTts();
      expect(flow.isTtsPlaying, isTrue);

      expect(flow.claimOption(), isTrue);
      expect(flow.markSubmitted(AnswerSource.option, messageId: 10), isTrue);
    });
  });

  group('재생과 녹음', () {
    test('재생 중에는 자동 녹음을 시작하지 않는다', () {
      final flow = AnswerFlowController()..beginQuestion(10);
      flow.beginTts();

      // 재생 중에 켜면 질문 소리가 그대로 답으로 녹음된다.
      expect(flow.canStartAutomaticVoice, isFalse);
      expect(flow.claimVoice(automatic: true), isFalse);

      flow.markAnswerReady();
      expect(flow.canStartAutomaticVoice, isTrue);
    });

    test('재생 중과 녹음 중이 동시에 참이 되지 않는다', () {
      final flow = AnswerFlowController()..beginQuestion(10);
      flow.beginTts();
      expect(flow.isTtsPlaying && flow.isVoiceRecording, isFalse);

      flow.markAnswerReady();
      flow.claimVoice(automatic: true);
      expect(flow.isTtsPlaying && flow.isVoiceRecording, isFalse);
    });

    test('TTS 실패도 답할 수 있는 상태로 넘어간다', () {
      final flow = AnswerFlowController()..beginQuestion(10);
      flow.beginTts();

      // 실패·성공·건너뜀이 같은 자리로 온다.
      flow.markAnswerReady();
      expect(flow.stage, AnswerFlowStage.answerReady);
    });
  });

  group('아이가 직접 시작한 녹음', () {
    test('보기가 가로채지 않는다', () {
      // 아이가 마이크를 눌러 말하는 중이라면 그건 이미 아이의 답이다.
      final flow = _readyFlow();
      flow.claimVoice(automatic: false);

      expect(flow.claimOption(), isFalse);
      expect(flow.markSubmitted(AnswerSource.voice, messageId: 10), isTrue);
    });
  });

  group('놓기', () {
    test('녹음을 취소하면 다시 답할 수 있다', () {
      final flow = _readyFlow();
      flow.claimVoice(automatic: true);

      flow.release(AnswerSource.voice);
      expect(flow.stage, AnswerFlowStage.answerReady);
      expect(flow.claimOption(), isTrue);
    });

    test('확정된 답은 놓아도 풀리지 않는다', () {
      final flow = _readyFlow();
      flow.claimOption();
      flow.markSubmitted(AnswerSource.option, messageId: 10);

      flow.release(AnswerSource.option);
      expect(flow.isSubmitted, isTrue);
    });
  });
}

/// 답할 수 있는 상태(TTS 끝남)의 흐름을 만든다.
AnswerFlowController _readyFlow() {
  final flow = AnswerFlowController()..beginQuestion(10);
  flow.beginTts();
  flow.markAnswerReady();
  return flow;
}
