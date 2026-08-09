import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../domain/services/voice_recorder.dart';

// 기기 마이크 입력을 앱 임시 저장소의 M4A 파일로 생성
final class DeviceVoiceRecorder implements VoiceRecorder {
  DeviceVoiceRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _activePath;

  @override
  Future<void> start() async {
    final directory = await getTemporaryDirectory();
    final voiceDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}voice_answers',
    );
    await voiceDirectory.create(recursive: true);

    final random = Random.secure().nextInt(1 << 32);
    final fileName =
        'voice-${DateTime.now().microsecondsSinceEpoch}-$random.m4a';
    final path = '${voiceDirectory.path}${Platform.pathSeparator}$fileName';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );
    _activePath = path;
  }

  @override
  Future<double> readAmplitude() async {
    final amplitude = await _recorder.getAmplitude();
    return amplitude.current;
  }

  @override
  Future<String?> stop() async {
    final savedPath = await _recorder.stop();
    _activePath = null;
    return savedPath;
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    final path = _activePath;
    _activePath = null;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
