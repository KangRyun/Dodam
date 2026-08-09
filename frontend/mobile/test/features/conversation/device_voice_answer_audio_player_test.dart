import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  var token = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dodam_voice_player_test_');
    token = 0;
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  DeviceVoiceAnswerAudioPlayer playerWith(List<_FakeAudioEngine> engines) =>
      DeviceVoiceAnswerAudioPlayer(
        engineFactory: () => engines.removeAt(0),
        temporaryDirectoryProvider: () async => root,
        randomTokenFactory: () =>
            'randomtoken${(token++).toString().padLeft(4, '0')}',
      );

  for (final entry in const {
    'audio/webm': '.webm',
    'audio/mp4; codecs=mp4a.40.2': '.m4a',
    'audio/wav': '.wav',
    'audio/mpeg': '.mp3',
  }.entries) {
    test('${entry.key} MIME으로 안전한 확장자와 정확한 path를 사용한다', () async {
      final engine = _FakeAudioEngine();
      final player = playerWith([engine]);
      final bytes = Uint8List.fromList([1, 2, 3]);

      final playback = player.play(bytes, mimeType: entry.key);
      await _waitFor(() => engine.paths.isNotEmpty);
      final path = engine.paths.single;

      expect(path, endsWith(entry.value));
      expect(engine.mimeTypes.single, entry.key.split(';').first);
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      engine.complete();
      await playback;

      expect(await File(path).exists(), isFalse);
      expect(bytes, everyElement(0));
      expect(engine.releaseCount, 1);
      expect(engine.disposeCount, 1);
    });
  }

  test('무작위 중립 파일명에 messageId나 민감 원문을 넣지 않는다', () async {
    final engine = _FakeAudioEngine();
    final player = playerWith([engine]);

    final playback = player.play(
      Uint8List.fromList([1]),
      mimeType: 'audio/webm',
    );
    await _waitFor(() => engine.paths.isNotEmpty);
    final filename = File(engine.paths.single).uri.pathSegments.last;

    expect(filename, 'voice_randomtoken0000.webm');
    expect(filename, isNot(contains('804')));
    expect(filename, isNot(contains('child')));
    engine.complete();
    await playback;
  });

  test('stop과 중복 stop은 handle 해제 뒤 파일을 안전하게 삭제한다', () async {
    final engine = _FakeAudioEngine();
    final player = playerWith([engine]);

    final playback = player.play(
      Uint8List.fromList([1]),
      mimeType: 'audio/webm',
    );
    await _waitFor(() => engine.paths.isNotEmpty);
    final path = engine.paths.single;

    await player.stop();
    await player.stop();
    await playback;

    expect(await File(path).exists(), isFalse);
    expect(engine.releaseCount, 1);
  });

  test('다른 재생은 A를 삭제하고 독립 engine으로 B만 유지한다', () async {
    final firstEngine = _FakeAudioEngine();
    final secondEngine = _FakeAudioEngine();
    final player = playerWith([firstEngine, secondEngine]);

    final first = player.play(Uint8List.fromList([1]), mimeType: 'audio/webm');
    await _waitFor(() => firstEngine.paths.isNotEmpty);
    final firstPath = firstEngine.paths.single;
    final second = player.play(Uint8List.fromList([2]), mimeType: 'audio/mpeg');
    await _waitFor(() => secondEngine.paths.isNotEmpty);
    final secondPath = secondEngine.paths.single;
    await first;

    expect(await File(firstPath).exists(), isFalse);
    expect(await File(secondPath).exists(), isTrue);

    var secondFinished = false;
    unawaited(second.then((_) => secondFinished = true));
    firstEngine.complete();
    firstEngine.fail(StateError('late A error'));
    await Future<void>.delayed(Duration.zero);
    expect(secondFinished, isFalse);
    expect(await File(secondPath).exists(), isTrue);

    secondEngine.complete();
    await second;
    expect(await File(secondPath).exists(), isFalse);
  });

  test('resume 초기화 실패도 원본 bytes와 부분 파일을 정리한다', () async {
    final engine = _FakeAudioEngine(resumeFailure: StateError('decode'));
    final player = playerWith([engine]);
    final bytes = Uint8List.fromList([1, 2, 3]);

    await expectLater(
      player.play(bytes, mimeType: 'audio/webm'),
      throwsStateError,
    );

    expect(await File(engine.paths.single).exists(), isFalse);
    expect(bytes, everyElement(0));
    expect(engine.releaseCount, 1);
    expect(engine.disposeCount, 1);
  });

  test('source 설정 실패도 생성된 파일을 삭제한다', () async {
    final engine = _FakeAudioEngine(sourceFailure: StateError('source'));
    final player = playerWith([engine]);

    await expectLater(
      player.play(Uint8List.fromList([1]), mimeType: 'audio/webm'),
      throwsStateError,
    );

    expect(await File(engine.paths.single).exists(), isFalse);
    expect(engine.releaseCount, 1);
    expect(engine.disposeCount, 1);
  });

  test('dispose는 진행 중 재생과 파일을 정리하고 늦은 이벤트를 무시한다', () async {
    final engine = _FakeAudioEngine();
    final player = playerWith([engine]);
    final playback = player.play(
      Uint8List.fromList([1]),
      mimeType: 'audio/webm',
    );
    await _waitFor(() => engine.paths.isNotEmpty);
    final path = engine.paths.single;

    await player.dispose();
    await playback;
    engine.complete();
    engine.fail(StateError('late'));

    expect(await File(path).exists(), isFalse);
    expect(engine.disposeCount, 1);
  });

  test('play 직후 stop은 파일을 만들거나 재생을 시작하지 않는다', () async {
    final engine = _FakeAudioEngine();
    final player = playerWith([engine]);
    final bytes = Uint8List.fromList([1]);

    final playback = player.play(bytes, mimeType: 'audio/webm');
    final stopping = player.stop();
    await Future.wait([playback, stopping]);

    expect(engine.paths, isEmpty);
    expect(bytes, everyElement(0));
  });

  test('stop 직후 새 play는 새 세션에서 정상 완료한다', () async {
    final firstEngine = _FakeAudioEngine();
    final secondEngine = _FakeAudioEngine();
    final player = playerWith([firstEngine, secondEngine]);
    final first = player.play(Uint8List.fromList([1]), mimeType: 'audio/webm');
    await _waitFor(() => firstEngine.paths.isNotEmpty);

    await player.stop();
    await first;
    final second = player.play(Uint8List.fromList([2]), mimeType: 'audio/webm');
    await _waitFor(() => secondEngine.paths.isNotEmpty);
    secondEngine.complete();
    await second;

    expect(firstEngine.releaseCount, 1);
    expect(secondEngine.releaseCount, 1);
  });

  test('지원하지 않는 MIME은 파일 생성 전 typed failure다', () async {
    final engine = _FakeAudioEngine();
    final player = playerWith([engine]);

    await expectLater(
      player.play(Uint8List.fromList([1]), mimeType: 'audio/unsupported'),
      throwsA(
        isA<VoiceAnswerPlaybackValidationFailure>().having(
          (failure) => failure.reason,
          'reason',
          VoiceAnswerPlaybackValidationReason.unsupportedMimeType,
        ),
      ),
    );

    expect(engine.paths, isEmpty);
  });

  test('temporary directory 초기화 실패에서도 원본 bytes를 지운다', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final player = DeviceVoiceAnswerAudioPlayer(
      engineFactory: _FakeAudioEngine.new,
      temporaryDirectoryProvider: () => Future<Directory>.error(
        FileSystemException('temporary directory unavailable'),
      ),
    );

    await expectLater(
      player.play(bytes, mimeType: 'audio/webm'),
      throwsA(isA<FileSystemException>()),
    );

    expect(bytes, everyElement(0));
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for asynchronous player transition');
}

final class _FakeAudioEngine implements VoiceAnswerAudioEngine {
  _FakeAudioEngine({this.sourceFailure, this.resumeFailure});

  final Object? sourceFailure;
  final Object? resumeFailure;
  final StreamController<void> _completed = StreamController<void>.broadcast(
    sync: true,
  );
  final StreamController<void> _stopped = StreamController<void>.broadcast(
    sync: true,
  );
  final List<String> paths = [];
  final List<String> mimeTypes = [];
  int releaseCount = 0;
  int disposeCount = 0;

  @override
  Stream<void> get onCompleted => _completed.stream;

  @override
  Stream<void> get onStopped => _stopped.stream;

  @override
  Future<void> setDeviceFile(String path, {required String mimeType}) async {
    paths.add(path);
    mimeTypes.add(mimeType);
    if (sourceFailure case final failure?) throw failure;
  }

  @override
  Future<void> resume() async {
    if (resumeFailure case final failure?) throw failure;
  }

  @override
  Future<void> release() async {
    releaseCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }

  void complete() => _completed.add(null);

  void fail(Object error) => _completed.addError(error);
}
