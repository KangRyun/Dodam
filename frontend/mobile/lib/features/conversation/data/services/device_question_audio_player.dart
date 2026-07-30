import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../../domain/services/question_audio_player.dart';

final class DeviceQuestionAudioPlayer implements QuestionAudioPlayer {
  DeviceQuestionAudioPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  int _command = 0;
  bool _disposed = false;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) async {
    if (_disposed) return;
    final command = ++_command;
    await _player.stop();
    if (_disposed || command != _command) return;
    await _player.setSourceBytes(bytes, mimeType: mimeType);
    if (_disposed || command != _command) return;
    final playbackCompleted = _player.onPlayerComplete.first;
    final playbackStopped = _player.onPlayerStateChanged.firstWhere(
      (state) => state == PlayerState.stopped,
    );
    await _player.resume();
    await Future.any<void>([playbackCompleted, playbackStopped]);
  }

  @override
  Future<void> stop() async {
    _command += 1;
    if (!_disposed) await _player.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _command += 1;
    await _player.dispose();
  }
}
