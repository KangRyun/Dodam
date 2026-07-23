import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/voice_recording.dart';
import '../domain/services/microphone_permission_service.dart';
import '../domain/services/voice_recorder.dart';

enum VoiceRecordingStatus {
  idle,
  starting,
  recording,
  awaitingChoice,
  stopping,
  completed,
  permissionDenied,
  permissionPermanentlyDenied,
  failed,
  interrupted,
}

final class VoiceRecordingController extends ChangeNotifier {
  VoiceRecordingController(
    this._recorder, {
    this.permissionService,
    this.noSpeechTimeout = const Duration(seconds: 3),
    this.postSpeechSilenceTimeout = const Duration(seconds: 3),
    this.maximumDuration = const Duration(minutes: 1),
    this.amplitudeSampleInterval = const Duration(milliseconds: 200),
    this.speechThreshold = -35,
  });

  final VoiceRecorder _recorder;
  final MicrophonePermissionService? permissionService;
  final Duration noSpeechTimeout;
  final Duration postSpeechSilenceTimeout;
  final Duration maximumDuration;
  final Duration amplitudeSampleInterval;
  final double speechThreshold;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  Timer? _amplitudeTimer;
  bool _readingAmplitude = false;

  VoiceRecordingStatus _status = VoiceRecordingStatus.idle;
  VoiceRecording? _recording;
  Object? _lastError;
  bool _hasDetectedSpeech = false;
  Duration? _lastSpeechAt;

  VoiceRecordingStatus get status => _status;
  VoiceRecording? get recording => _recording;
  Object? get lastError => _lastError;
  bool get hasDetectedSpeech => _hasDetectedSpeech;
  bool get shouldShowOptions =>
      _status == VoiceRecordingStatus.awaitingChoice ||
      _status == VoiceRecordingStatus.permissionDenied ||
      _status == VoiceRecordingStatus.permissionPermanentlyDenied ||
      _status == VoiceRecordingStatus.failed ||
      _status == VoiceRecordingStatus.interrupted;
  Duration get elapsed => _stopwatch.elapsed;
  bool get isRecording => _status == VoiceRecordingStatus.recording;
  bool get isBusy =>
      _status == VoiceRecordingStatus.starting ||
      _status == VoiceRecordingStatus.stopping;

  // 새 음성 답변 녹음 시작
  Future<bool> start() async {
    if (_status == VoiceRecordingStatus.starting ||
        _status == VoiceRecordingStatus.recording ||
        _status == VoiceRecordingStatus.stopping) {
      return false;
    }

    _status = VoiceRecordingStatus.starting;
    notifyListeners();
    final permissionStatus = await permissionService?.request();
    if (permissionStatus == MicrophonePermissionStatus.denied) {
      _status = VoiceRecordingStatus.permissionDenied;
      notifyListeners();
      return false;
    }
    if (permissionStatus == MicrophonePermissionStatus.permanentlyDenied) {
      _status = VoiceRecordingStatus.permissionPermanentlyDenied;
      notifyListeners();
      return false;
    }
    if (_status != VoiceRecordingStatus.starting) return false;

    _recording = null;
    _lastError = null;
    _hasDetectedSpeech = false;
    _lastSpeechAt = null;
    notifyListeners();
    try {
      await _recorder.start();
      if (_status != VoiceRecordingStatus.starting) {
        await _recorder.cancel();
        return false;
      }
      _stopwatch
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        notifyListeners();
      });
      _amplitudeTimer = Timer.periodic(
        amplitudeSampleInterval,
        (_) => unawaited(_checkAmplitude()),
      );
      _status = VoiceRecordingStatus.recording;
      notifyListeners();
      return true;
    } on Object catch (error) {
      _lastError = error;
      _status = VoiceRecordingStatus.failed;
      notifyListeners();
      return false;
    }
  }

  // 영구 거부된 마이크 권한을 변경할 수 있도록 앱 설정 열기
  Future<bool> openPermissionSettings() async =>
      await permissionService?.openSettings() ?? false;

  // 녹음을 종료하고 생성된 로컬 파일 정보 보관
  Future<VoiceRecording?> stop({
    VoiceRecordingCompletionReason reason =
        VoiceRecordingCompletionReason.manual,
  }) async {
    if (_status != VoiceRecordingStatus.recording) return null;

    _status = VoiceRecordingStatus.stopping;
    notifyListeners();
    _ticker?.cancel();
    _ticker = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _stopwatch.stop();
    final duration = _stopwatch.elapsed;
    try {
      final path = await _recorder.stop();
      if (path == null || path.isEmpty) {
        throw StateError('Recorded file path is missing');
      }
      final result = VoiceRecording(
        filePath: path,
        duration: duration,
        completionReason: reason,
      );
      _recording = result;
      _status = VoiceRecordingStatus.completed;
      notifyListeners();
      return result;
    } on Object catch (error) {
      _lastError = error;
      _status = VoiceRecordingStatus.failed;
      notifyListeners();
      return null;
    }
  }

  // 앱 전환이나 통화 등으로 중단된 녹음 폐기
  Future<void> interrupt() async {
    if (_status != VoiceRecordingStatus.recording &&
        _status != VoiceRecordingStatus.starting) {
      return;
    }
    await _discardActiveRecording(VoiceRecordingStatus.interrupted);
  }

  // 진행 중인 음성 답변을 폐기하고 대기 상태로 복귀
  Future<void> cancel() async {
    if (_status != VoiceRecordingStatus.recording &&
        _status != VoiceRecordingStatus.starting) {
      return;
    }

    _ticker?.cancel();
    _ticker = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _stopwatch
      ..stop()
      ..reset();
    try {
      await _recorder.cancel();
    } on Object catch (error) {
      _lastError = error;
    }
    _recording = null;
    _status = VoiceRecordingStatus.idle;
    notifyListeners();
  }

  // 음성이 없으면 녹음을 폐기하고 선택지 응답으로 전환
  Future<void> _checkAmplitude() async {
    if (_readingAmplitude || _status != VoiceRecordingStatus.recording) return;
    _readingAmplitude = true;
    try {
      final amplitude = await _recorder.readAmplitude();
      final elapsed = _stopwatch.elapsed;
      if (amplitude >= speechThreshold) {
        _lastSpeechAt = elapsed;
        if (!_hasDetectedSpeech) {
          _hasDetectedSpeech = true;
          notifyListeners();
        }
      }
      if (!_hasDetectedSpeech && elapsed >= noSpeechTimeout) {
        await _moveToChoice();
        return;
      }
      final lastSpeechAt = _lastSpeechAt;
      if (_hasDetectedSpeech &&
          lastSpeechAt != null &&
          elapsed - lastSpeechAt >= postSpeechSilenceTimeout) {
        await stop(reason: VoiceRecordingCompletionReason.silence);
        return;
      }
      if (elapsed >= maximumDuration) {
        if (_hasDetectedSpeech) {
          await stop(reason: VoiceRecordingCompletionReason.maximumDuration);
        } else {
          await _moveToChoice();
        }
      }
    } on Object catch (error) {
      _lastError = error;
      await _discardActiveRecording(VoiceRecordingStatus.failed);
    } finally {
      _readingAmplitude = false;
    }
  }

  Future<void> _moveToChoice() async {
    if (_status != VoiceRecordingStatus.recording) return;
    await _discardActiveRecording(VoiceRecordingStatus.awaitingChoice);
  }

  Future<void> _discardActiveRecording(VoiceRecordingStatus nextStatus) async {
    _ticker?.cancel();
    _ticker = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _stopwatch
      ..stop()
      ..reset();
    try {
      await _recorder.cancel();
    } on Object catch (error) {
      _lastError = error;
    }
    _recording = null;
    _status = nextStatus;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _amplitudeTimer?.cancel();
    if (isRecording || _status == VoiceRecordingStatus.stopping) {
      unawaited(_recorder.cancel());
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
