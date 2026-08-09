import 'dart:typed_data';

import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 질문 음성이 끊기는 자리마다 다음 수단으로 넘어가는지 확인한다 (P0-3).
///
/// 실측(2026-08-08)에서 5문항 전부 무음이었고, 재생 버튼을 눌러도 아무 일도 일어나지 않았다.
/// messageId 당 한 번만 시도하는 가드가 재생 버튼까지 막고 있었기 때문이다.
void main() {
  final question = AiQuestion(
    messageId: 7001,
    conversationId: 70,
    sequence: 1,
    text: '무엇을 그렸어?',
    options: const [],
    ttsAvailable: true,
    createdAt: DateTime.utc(2026, 8, 8),
  );

  AiQuestionTtsController controller({
    required _Repository repository,
    _Synthesizer? synthesizer,
    _Player? player,
  }) => AiQuestionTtsController(
    repository,
    player ?? _Player(),
    synthesizer: synthesizer ?? _Synthesizer(canSpeak: false),
    retryDelay: Duration.zero,
  );

  test('서버가 한 번 흔들리면 다시 시도해 소리를 낸다', () async {
    final repository = _Repository(failuresBeforeSuccess: 1);
    final player = _Player();

    await controller(repository: repository, player: player).playQuestion(
      question,
    );

    expect(repository.calls, 2);
    expect(player.playCount, 1);
  });

  test('서버가 두 번 다 실패하면 기기 음성으로 읽어 준다', () async {
    final repository = _Repository(failuresBeforeSuccess: 99);
    final synthesizer = _Synthesizer(canSpeak: true);

    final tts = controller(repository: repository, synthesizer: synthesizer);
    await tts.playQuestion(question);

    expect(repository.calls, 2);
    expect(synthesizer.spoken, ['무엇을 그렸어?']);
    expect(tts.usedDeviceFallback, isTrue);
    expect(tts.status, AiQuestionTtsStatus.playing);
    // 소리는 났으니 재생 버튼을 굳이 띄우지 않는다.
    expect(tts.needsManualReplay, isFalse);
  });

  test('기기 음성도 없으면 수동 재생 버튼만 남는다', () async {
    final repository = _Repository(failuresBeforeSuccess: 99);

    final tts = controller(repository: repository);
    await tts.playQuestion(question);

    expect(tts.status, AiQuestionTtsStatus.failure);
    expect(tts.needsManualReplay, isTrue);
    expect(tts.usedDeviceFallback, isFalse);
  });

  test('재생 버튼은 자동 재생 가드를 지나친다', () async {
    final repository = _Repository(failuresBeforeSuccess: 99);
    final tts = controller(repository: repository);

    await tts.playQuestion(question);
    expect(repository.calls, 2);

    // 같은 질문에 두 번째 자동 재생은 여전히 막는다 — 겹쳐 들리면 안 된다.
    await tts.playQuestion(question);
    expect(repository.calls, 2);

    // 사람이 누른 것은 다르다. 여기가 막혀 있어서 실측에서 버튼이 죽어 있었다.
    await tts.replayQuestion(question);
    expect(repository.calls, 4);
  });

  test('기기 음성이 성공한 뒤 다음 질문으로 넘어가면 앞의 음성을 멈춘다', () async {
    final synthesizer = _Synthesizer(canSpeak: true);
    final tts = controller(
      repository: _Repository(failuresBeforeSuccess: 99),
      synthesizer: synthesizer,
    );

    await tts.playQuestion(question);
    await tts.stop();

    expect(synthesizer.stopCount, greaterThan(0));
    expect(tts.status, AiQuestionTtsStatus.idle);
    expect(tts.usedDeviceFallback, isFalse);
  });
}

final class _Repository implements QuestionTtsRepository {
  _Repository({required this.failuresBeforeSuccess});

  final int failuresBeforeSuccess;
  int calls = 0;

  @override
  Future<QuestionTtsAudio> loadQuestionAudio(
    int messageId, {
    QuestionTtsRequest request = const QuestionTtsRequest(),
  }) async {
    calls += 1;
    if (calls <= failuresBeforeSuccess) {
      throw StateError('tts unavailable');
    }
    return QuestionTtsAudio(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'audio/mpeg',
    );
  }
}

final class _Player implements QuestionAudioPlayer {
  int playCount = 0;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) async {
    playCount += 1;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

final class _Synthesizer implements QuestionSpeechSynthesizer {
  _Synthesizer({required this.canSpeak});

  final bool canSpeak;
  final List<String> spoken = [];
  int stopCount = 0;

  @override
  Future<bool> speak(String text) async {
    if (!canSpeak) return false;
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}
