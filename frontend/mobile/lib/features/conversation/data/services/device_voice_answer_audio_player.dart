import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models/voice_answer_audio.dart';
import '../../domain/services/voice_answer_audio_player.dart';

typedef VoiceAnswerTemporaryDirectoryProvider = Future<Directory> Function();
typedef VoiceAnswerRandomTokenFactory = String Function();
typedef VoiceAnswerAudioEngineFactory = VoiceAnswerAudioEngine Function();

/// OS codec 호출과 임시 파일 수명주기를 분리하기 위한 경계다.
abstract interface class VoiceAnswerAudioEngine {
  Stream<void> get onCompleted;

  Stream<void> get onStopped;

  Future<void> setDeviceFile(String path, {required String mimeType});

  Future<void> resume();

  Future<void> release();

  Future<void> dispose();
}

/// 앱이 통제하는 단일 임시 파일로 아동 음성을 재생한다.
///
/// 파일 생성부터 삭제까지 이 클래스만 소유하며, player handle을 [release]한
/// 뒤 best-effort로 삭제한다.
final class DeviceVoiceAnswerAudioPlayer implements VoiceAnswerAudioPlayer {
  DeviceVoiceAnswerAudioPlayer({
    VoiceAnswerAudioEngineFactory? engineFactory,
    VoiceAnswerTemporaryDirectoryProvider? temporaryDirectoryProvider,
    VoiceAnswerRandomTokenFactory? randomTokenFactory,
  }) : _engineFactory =
           engineFactory ?? _AudioplayersVoiceAnswerAudioEngine.new,
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _randomTokenFactory = randomTokenFactory ?? _secureRandomToken;

  final VoiceAnswerAudioEngineFactory _engineFactory;
  final VoiceAnswerTemporaryDirectoryProvider _temporaryDirectoryProvider;
  final VoiceAnswerRandomTokenFactory _randomTokenFactory;

  Future<void> _transitionTail = Future<void>.value();
  _PlaybackSession? _activeSession;
  int _command = 0;
  bool _disposed = false;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) async {
    if (_disposed) {
      _wipe(bytes);
      return;
    }
    final command = ++_command;
    _PlaybackSession? session;
    try {
      session = await _serialize(
        () => _preparePlayback(bytes, mimeType: mimeType, command: command),
      );
      if (session == null) return;
      await session.done;
    } finally {
      _wipe(bytes);
      await session?.cancelSubscriptions();
      if (session != null) {
        await _serialize(() => _cleanupOwnedSession(session!));
      }
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _command += 1;
    await _serialize(_releaseAndDeleteActiveSession);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _command += 1;
    await _serialize(_releaseAndDeleteActiveSession);
  }

  Future<_PlaybackSession?> _preparePlayback(
    Uint8List bytes, {
    required String mimeType,
    required int command,
  }) async {
    final normalizedMimeType = _normalizedMimeType(mimeType);
    final extension = _extensionFor(normalizedMimeType);
    await _releaseAndDeleteActiveSession();
    if (!_isCurrent(command)) return null;

    File? file;
    try {
      file = await _createTemporaryFile(extension);
      await file.writeAsBytes(bytes, flush: true);
      if (!_isCurrent(command)) {
        await _deleteBestEffort(file);
        return null;
      }

      final session = _PlaybackSession(file, _engineFactory());
      _activeSession = session;
      await session.engine.setDeviceFile(
        file.path,
        mimeType: normalizedMimeType,
      );
      if (!_isCurrent(command)) {
        await _cleanupOwnedSession(session);
        return null;
      }

      session.listen();
      await session.engine.resume();
      if (!_isCurrent(command)) {
        await _cleanupOwnedSession(session);
        return null;
      }
      return session;
    } on Object {
      final active = _activeSession;
      if (active != null && identical(active.file, file)) {
        await _cleanupOwnedSession(active);
      } else if (file != null) {
        await _deleteBestEffort(file);
      }
      rethrow;
    }
  }

  Future<File> _createTemporaryFile(String extension) async {
    final root = await _temporaryDirectoryProvider();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}dodam_voice_playback',
    );
    await directory.create(recursive: true);

    for (var attempt = 0; attempt < 4; attempt += 1) {
      final token = _randomTokenFactory();
      if (!_safeToken.hasMatch(token)) {
        throw StateError('Invalid temporary audio token');
      }
      final file = File(
        '${directory.path}${Platform.pathSeparator}voice_$token.$extension',
      );
      try {
        return await file.create(exclusive: true);
      } on FileSystemException {
        if (attempt == 3) rethrow;
      }
    }
    throw StateError('Unable to create temporary audio file');
  }

  Future<void> _releaseAndDeleteActiveSession() async {
    final session = _activeSession;
    if (session == null) return;
    _activeSession = null;
    session.finish();
    try {
      await session.engine.release();
    } on Object {
      // handle 해제 실패와 무관하게 민감 파일 삭제는 계속 시도한다.
    }
    try {
      await session.engine.dispose();
    } on Object {
      // engine dispose 실패도 민감 파일 삭제를 막지 않는다.
    }
    await _deleteBestEffort(session.file);
  }

  Future<void> _cleanupOwnedSession(_PlaybackSession session) async {
    if (identical(_activeSession, session)) {
      await _releaseAndDeleteActiveSession();
      return;
    }
    await _deleteBestEffort(session.file);
  }

  bool _isCurrent(int command) => !_disposed && command == _command;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final previous = _transitionTail;
    final result = Completer<T>();
    _transitionTail = result.future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    unawaited(_runSerialized(previous, action, result));
    return result.future;
  }
}

final class _PlaybackSession {
  _PlaybackSession(this.file, this.engine);

  final File file;
  final VoiceAnswerAudioEngine engine;
  final Completer<void> _done = Completer<void>();
  StreamSubscription<void>? _completedSubscription;
  StreamSubscription<void>? _stoppedSubscription;

  Future<void> get done => _done.future;

  void listen() {
    _completedSubscription = engine.onCompleted.listen(
      (_) => finish(),
      onError: fail,
    );
    _stoppedSubscription = engine.onStopped.listen(
      (_) => finish(),
      onError: fail,
    );
  }

  void finish() {
    if (!_done.isCompleted) _done.complete();
  }

  void fail(Object error, StackTrace stackTrace) {
    if (!_done.isCompleted) _done.completeError(error, stackTrace);
  }

  Future<void> cancelSubscriptions() async {
    try {
      await _completedSubscription?.cancel();
    } on Object {
      // subscription 정리 실패가 파일 삭제를 막지 않게 한다.
    }
    try {
      await _stoppedSubscription?.cancel();
    } on Object {
      // subscription 정리 실패가 파일 삭제를 막지 않게 한다.
    }
  }
}

final class _AudioplayersVoiceAnswerAudioEngine
    implements VoiceAnswerAudioEngine {
  _AudioplayersVoiceAnswerAudioEngine() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get onCompleted => _player.onPlayerComplete;

  @override
  Stream<void> get onStopped => _player.onPlayerStateChanged
      .where((state) => state == PlayerState.stopped)
      .map((_) {});

  @override
  Future<void> setDeviceFile(String path, {required String mimeType}) =>
      _player.setSource(DeviceFileSource(path, mimeType: mimeType));

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> release() => _player.release();

  @override
  Future<void> dispose() => _player.dispose();
}

Future<void> _runSerialized<T>(
  Future<void> previous,
  Future<T> Function() action,
  Completer<T> result,
) async {
  await previous;
  try {
    result.complete(await action());
  } on Object catch (error, stackTrace) {
    result.completeError(error, stackTrace);
  }
}

Future<void> _deleteBestEffort(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on Object {
    // 삭제 실패를 UI 오류나 민감한 절대 경로 로그로 노출하지 않는다.
  }
}

void _wipe(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}

String _normalizedMimeType(String mimeType) =>
    mimeType.split(';').first.trim().toLowerCase();

String _extensionFor(String mimeType) => switch (mimeType) {
  'audio/webm' => 'webm',
  'audio/mp4' => 'm4a',
  'audio/wav' => 'wav',
  'audio/mpeg' => 'mp3',
  _ => throw const VoiceAnswerPlaybackValidationFailure(
    VoiceAnswerPlaybackValidationReason.unsupportedMimeType,
  ),
};

String _secureRandomToken() {
  final random = Random.secure();
  return List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    growable: false,
  ).join();
}

final RegExp _safeToken = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
