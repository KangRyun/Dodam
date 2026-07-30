import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('idle → loading → playing → completed로 전이한다', () async {
    final load = Completer<VoiceAnswerAudio>();
    final playback = Completer<void>();
    final repository = _PlaybackRepository(response: load.future);
    final player = _PlaybackPlayer(completion: playback);
    final controller = VoiceAnswerPlaybackController(repository, player);

    final request = controller.play(804);
    expect(controller.status, VoiceAnswerPlaybackStatus.loading);
    load.complete(_audio());
    await _flush();
    expect(controller.status, VoiceAnswerPlaybackStatus.playing);
    playback.complete();
    await request;

    expect(controller.status, VoiceAnswerPlaybackStatus.completed);
    expect(repository.messageIds, [804]);
    expect(player.playCount, 1);
  });

  test('loading 중 중복 탭은 load와 play를 한 번만 실행한다', () async {
    final load = Completer<VoiceAnswerAudio>();
    final repository = _PlaybackRepository(response: load.future);
    final player = _PlaybackPlayer();
    final controller = VoiceAnswerPlaybackController(repository, player);

    final first = controller.play(804);
    final duplicate = controller.play(804);
    load.complete(_audio());
    await Future.wait([first, duplicate]);

    expect(repository.messageIds, [804]);
    expect(player.playCount, 1);
  });

  test('playing에서 stop하면 stopped가 되고 중복 stop도 안전하다', () async {
    final playback = Completer<void>();
    final player = _PlaybackPlayer(completion: playback);
    final controller = VoiceAnswerPlaybackController(
      _PlaybackRepository(),
      player,
    );
    final request = controller.play(804);
    await _flush();
    expect(controller.status, VoiceAnswerPlaybackStatus.playing);

    await controller.stop();
    await controller.stop();
    playback.complete();
    await request;

    expect(controller.status, VoiceAnswerPlaybackStatus.stopped);
    expect(player.stopCount, greaterThanOrEqualTo(3));
  });

  test('완료 후 같은 음성을 다시 재생하면 서버에서 다시 조회한다', () async {
    final repository = _PlaybackRepository();
    final player = _PlaybackPlayer();
    final controller = VoiceAnswerPlaybackController(repository, player);

    await controller.play(804);
    await controller.play(804);

    expect(repository.messageIds, [804, 804]);
    expect(player.playCount, 2);
  });

  test('다른 메시지 재생은 기존 재생을 정리하고 늦은 응답을 무시한다', () async {
    final first = Completer<VoiceAnswerAudio>();
    final repository = _PlaybackRepository(firstResponse: first.future);
    final player = _PlaybackPlayer();
    final controller = VoiceAnswerPlaybackController(repository, player);

    final stale = controller.play(804);
    await _flush();
    await controller.play(806);
    first.complete(_audio());
    await stale;

    expect(controller.activeMessageId, 806);
    expect(controller.status, VoiceAnswerPlaybackStatus.completed);
    expect(repository.messageIds, [804, 806]);
    expect(player.playCount, 1);
  });

  test('일시 오류는 retry를 허용하고 영구 오류는 차단한다', () async {
    final transient = VoiceAnswerPlaybackController(
      _PlaybackRepository(
        failure: const ApiResponseFailure(statusCode: 503, error: null),
      ),
      _PlaybackPlayer(),
    );
    final permanent = VoiceAnswerPlaybackController(
      _PlaybackRepository(
        failure: const ApiResponseFailure(statusCode: 404, error: null),
      ),
      _PlaybackPlayer(),
    );

    await transient.play(804);
    await permanent.play(804);

    expect(transient.status, VoiceAnswerPlaybackStatus.failure);
    expect(transient.canRetry, isTrue);
    expect(permanent.status, VoiceAnswerPlaybackStatus.failure);
    expect(permanent.canRetry, isFalse);
  });

  for (final reason in VoiceAnswerPlaybackValidationReason.values) {
    test('$reason 검증 오류는 retry를 차단한다', () async {
      final controller = VoiceAnswerPlaybackController(
        _PlaybackRepository(
          failure: VoiceAnswerPlaybackValidationFailure(reason),
        ),
        _PlaybackPlayer(),
      );

      await controller.play(804);

      expect(controller.status, VoiceAnswerPlaybackStatus.failure);
      expect(controller.canRetry, isFalse);
    });
  }

  test('유효하지 않은 messageId는 load 없이 명시적 failure가 된다', () async {
    final repository = _PlaybackRepository();
    final controller = VoiceAnswerPlaybackController(
      repository,
      _PlaybackPlayer(),
    );

    await controller.play(0);

    expect(repository.messageIds, isEmpty);
    expect(controller.status, VoiceAnswerPlaybackStatus.failure);
    expect(
      controller.error,
      isA<VoiceAnswerPlaybackValidationFailure>().having(
        (failure) => failure.reason,
        'reason',
        VoiceAnswerPlaybackValidationReason.invalidMessageId,
      ),
    );
    expect(controller.canRetry, isFalse);
  });

  test('stop과 다른 play는 진행 중인 다운로드를 취소한다', () async {
    final repository = _PlaybackRepository(pendingUntilCancelled: {804, 806});
    final controller = VoiceAnswerPlaybackController(
      repository,
      _PlaybackPlayer(),
    );

    final first = controller.play(804);
    await _flush();
    final second = controller.play(806);
    await _flush();
    await controller.stop();
    await Future.wait([first, second]);

    expect(repository.cancelledMessageIds, [804, 806]);
    expect(controller.status, VoiceAnswerPlaybackStatus.stopped);
    expect(controller.error, isNull);
  });

  test('dispose는 진행 중인 다운로드를 취소하고 오류를 노출하지 않는다', () async {
    final repository = _PlaybackRepository(pendingUntilCancelled: {804});
    final controller = VoiceAnswerPlaybackController(
      repository,
      _PlaybackPlayer(),
    );

    final request = controller.play(804);
    await _flush();
    controller.dispose();
    await request;

    expect(repository.cancelledMessageIds, [804]);
  });

  test('A의 늦은 player 오류가 완료된 B 상태를 바꾸지 않는다', () async {
    final firstPlayback = Completer<void>();
    final secondPlayback = Completer<void>();
    final player = _SequencedPlaybackPlayer([
      firstPlayback.future,
      secondPlayback.future,
    ]);
    final controller = VoiceAnswerPlaybackController(
      _PlaybackRepository(),
      player,
    );

    final first = controller.play(804);
    await _flush();
    final second = controller.play(806);
    await _flush();
    secondPlayback.complete();
    await second;
    firstPlayback.completeError(StateError('late A decode error'));
    await first;

    expect(controller.activeMessageId, 806);
    expect(controller.status, VoiceAnswerPlaybackStatus.completed);
    expect(controller.error, isNull);
  });

  test('player failure를 failure로 바꾸고 다음 재시도는 다시 load한다', () async {
    final repository = _PlaybackRepository();
    final player = _PlaybackPlayer(failure: StateError('decode'));
    final controller = VoiceAnswerPlaybackController(repository, player);

    await controller.play(804);
    expect(controller.status, VoiceAnswerPlaybackStatus.failure);
    player.failure = null;
    await controller.play(804);

    expect(controller.status, VoiceAnswerPlaybackStatus.completed);
    expect(repository.messageIds, [804, 804]);
  });

  test('reset과 dispose 뒤 늦은 load·completion은 상태를 바꾸지 않는다', () async {
    final load = Completer<VoiceAnswerAudio>();
    final repository = _PlaybackRepository(response: load.future);
    final player = _PlaybackPlayer();
    final controller = VoiceAnswerPlaybackController(repository, player);

    final request = controller.play(804);
    await controller.reset();
    load.complete(_audio());
    await request;

    expect(controller.status, VoiceAnswerPlaybackStatus.idle);
    expect(controller.activeMessageId, isNull);

    final late = Completer<VoiceAnswerAudio>();
    final disposedPlayer = _PlaybackPlayer();
    final disposedController = VoiceAnswerPlaybackController(
      _PlaybackRepository(response: late.future),
      disposedPlayer,
    );
    final disposedRequest = disposedController.play(806);
    disposedController.dispose();
    late.complete(_audio());
    await disposedRequest;
    await _flush();

    expect(disposedPlayer.playCount, 0);
    expect(disposedPlayer.disposeCount, 1);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

VoiceAnswerAudio _audio() => VoiceAnswerAudio(
  bytes: Uint8List.fromList([1, 2, 3]),
  mimeType: 'audio/webm',
);

final class _PlaybackRepository implements VoiceAnswerPlaybackRepository {
  _PlaybackRepository({
    this.response,
    this.firstResponse,
    this.failure,
    this.pendingUntilCancelled = const {},
  });

  final Future<VoiceAnswerAudio>? response;
  final Future<VoiceAnswerAudio>? firstResponse;
  final Object? failure;
  final Set<int> pendingUntilCancelled;
  final List<int> messageIds = [];
  final List<int> cancelledMessageIds = [];

  @override
  Future<VoiceAnswerAudio> loadVoiceAnswerAudio(
    int messageId, {
    VoiceAnswerPlaybackCancellation? cancellation,
  }) async {
    messageIds.add(messageId);
    if (pendingUntilCancelled.contains(messageId)) {
      await cancellation!.whenCancelled;
      cancelledMessageIds.add(messageId);
      throw const ApiTransportFailure(type: ApiTransportFailureType.cancelled);
    }
    if (failure case final caught?) throw caught;
    if (messageId == 804 && firstResponse != null) return firstResponse!;
    return response ?? _audio();
  }
}

final class _PlaybackPlayer implements VoiceAnswerAudioPlayer {
  _PlaybackPlayer({this.completion, this.failure});

  final Completer<void>? completion;
  Object? failure;
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) async {
    playCount += 1;
    if (failure case final caught?) throw caught;
    await (completion?.future ?? Future<void>.value());
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

final class _SequencedPlaybackPlayer implements VoiceAnswerAudioPlayer {
  _SequencedPlaybackPlayer(this.completions);

  final List<Future<void>> completions;
  int _index = 0;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) =>
      completions[_index++];

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
