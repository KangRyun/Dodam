import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('질문 도착 시 load와 play를 한 번만 실행하고 rebuild를 dedupe한다', () async {
    final repository = _FakeTtsRepository();
    final player = _FakeQuestionAudioPlayer();
    final controller = AiQuestionTtsController(repository, player);

    await Future.wait([
      controller.playQuestion(_question(1)),
      controller.playQuestion(_question(1)),
    ]);
    await controller.playQuestion(_question(1));

    expect(repository.messageIds, [1]);
    expect(player.playCount, 1);
    expect(controller.status, AiQuestionTtsStatus.playing);
  });

  test('ttsAvailable=false이면 요청·재생하지 않는다', () async {
    final repository = _FakeTtsRepository();
    final player = _FakeQuestionAudioPlayer();
    final controller = AiQuestionTtsController(repository, player);

    await controller.playQuestion(_question(1, ttsAvailable: false));

    expect(repository.messageIds, isEmpty);
    expect(player.playCount, 0);
  });

  test('새 질문은 이전 재생을 중단하고 새 음성을 재생한다', () async {
    final repository = _FakeTtsRepository();
    final player = _FakeQuestionAudioPlayer();
    final controller = AiQuestionTtsController(repository, player);

    await controller.playQuestion(_question(1));
    final stopsAfterFirst = player.stopCount;
    await controller.playQuestion(_question(2));

    expect(repository.messageIds, [1, 2]);
    expect(player.playCount, 2);
    expect(player.stopCount, greaterThan(stopsAfterFirst));
  });

  test('이전 질문의 늦은 응답은 새 질문 위에서 재생되지 않는다', () async {
    final first = Completer<QuestionTtsAudio>();
    final repository = _FakeTtsRepository(firstResponse: first.future);
    final player = _FakeQuestionAudioPlayer();
    final controller = AiQuestionTtsController(repository, player);

    final oldRequest = controller.playQuestion(_question(1));
    await Future<void>.delayed(Duration.zero);
    await controller.playQuestion(_question(2));
    first.complete(_audio);
    await oldRequest;

    expect(repository.messageIds, [1, 2]);
    expect(player.playCount, 1);
  });

  test('합성·다운로드 실패는 예외를 전파하지 않고 텍스트 흐름을 유지한다', () async {
    final repository = _FakeTtsRepository(failure: StateError('failed'));
    final player = _FakeQuestionAudioPlayer();
    final controller = AiQuestionTtsController(repository, player);

    await controller.playQuestion(_question(1));

    expect(controller.status, AiQuestionTtsStatus.failure);
    expect(controller.error, isA<StateError>());
    expect(player.playCount, 0);
  });

  test('재생 실패도 예외를 전파하지 않는다', () async {
    final controller = AiQuestionTtsController(
      _FakeTtsRepository(),
      _FakeQuestionAudioPlayer(playFailure: StateError('failed')),
    );

    await controller.playQuestion(_question(1));

    expect(controller.status, AiQuestionTtsStatus.failure);
  });

  test('답변·skip·end·navigation 경계의 stop은 재생을 중단한다', () async {
    final player = _FakeQuestionAudioPlayer();
    final controller = AiQuestionTtsController(_FakeTtsRepository(), player);
    await controller.playQuestion(_question(1));

    await controller.stop();

    expect(controller.status, AiQuestionTtsStatus.idle);
    expect(player.stopCount, greaterThanOrEqualTo(2));
  });
}

AiQuestion _question(int messageId, {bool ttsAvailable = true}) => AiQuestion(
  messageId: messageId,
  conversationId: 10,
  sequence: messageId,
  text: '무엇이 보이니?',
  options: const [],
  ttsAvailable: ttsAvailable,
  createdAt: DateTime.utc(2026, 7, 29),
);

final _audio = QuestionTtsAudio(
  bytes: Uint8List.fromList([1, 2, 3]),
  mimeType: 'audio/mpeg',
);

final class _FakeTtsRepository implements QuestionTtsRepository {
  _FakeTtsRepository({this.firstResponse, this.failure});

  final Future<QuestionTtsAudio>? firstResponse;
  final Object? failure;
  final List<int> messageIds = [];

  @override
  Future<QuestionTtsAudio> loadQuestionAudio(
    int messageId, {
    QuestionTtsRequest request = const QuestionTtsRequest(),
  }) async {
    messageIds.add(messageId);
    if (failure case final caught?) throw caught;
    if (messageId == 1 && firstResponse != null) return firstResponse!;
    return _audio;
  }
}

final class _FakeQuestionAudioPlayer implements QuestionAudioPlayer {
  _FakeQuestionAudioPlayer({this.playFailure});

  final Object? playFailure;
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) async {
    playCount += 1;
    if (playFailure case final caught?) throw caught;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
