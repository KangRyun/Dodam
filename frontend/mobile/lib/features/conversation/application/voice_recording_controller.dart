import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/voice_recording.dart';
import '../domain/services/microphone_permission_service.dart';
import '../domain/services/voice_recorder.dart';

enum VoiceRecordingStatus {
  idle,
  preparing,
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
    this.beforeStart,
  });

  final VoiceRecorder _recorder;
  final MicrophonePermissionService? permissionService;
  final Duration noSpeechTimeout;
  final Duration postSpeechSilenceTimeout;
  final Duration maximumDuration;
  final Duration amplitudeSampleInterval;
  final double speechThreshold;
  final Future<void> Function()? beforeStart;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  Timer? _amplitudeTimer;
  bool _readingAmplitude = false;
  int _operationGeneration = 0;
  bool _disposed = false;
  Future<void>? _pendingRecorderStart;
  Future<String?>? _pendingRecorderStop;
  Future<void>? _discardOperation;
  VoiceRecordingStatus? _discardTargetStatus;

  VoiceRecordingStatus _status = VoiceRecordingStatus.idle;
  VoiceRecording? _recording;
  Object? _lastError;
  bool _hasDetectedSpeech = false;
  Duration? _lastSpeechAt;
  DateTime? _startedAt;

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
      _status == VoiceRecordingStatus.preparing ||
      _status == VoiceRecordingStatus.starting ||
      _status == VoiceRecordingStatus.stopping ||
      _discardOperation != null ||
      _pendingRecorderStart != null ||
      _pendingRecorderStop != null;

  bool _isCurrentOperation(int generation) =>
      !_disposed && generation == _operationGeneration;

  bool _isCurrentStart(int generation) =>
      _isCurrentOperation(generation) &&
      _status == VoiceRecordingStatus.starting;

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  // 질문 음성을 들려주는 동안 수동 녹음 버튼이 먼저 노출되지 않게 한다.
  void prepareForAutomaticStart() {
    if (_disposed || _status != VoiceRecordingStatus.idle) return;
    _status = VoiceRecordingStatus.preparing;
    _notifyIfActive();
  }

  // 새 질문에서는 이전 질문의 녹음 결과와 오류 상태를 재사용하지 않는다.
  Future<void> beginQuestion() async {
    if (_disposed) return;
    if (_discardOperation case final discard?) await discard;
    if (_disposed) return;
    if (_status == VoiceRecordingStatus.starting ||
        _status == VoiceRecordingStatus.recording ||
        _status == VoiceRecordingStatus.stopping) {
      await cancel();
    }
    if (_disposed) return;
    _operationGeneration += 1;
    _ticker?.cancel();
    _ticker = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _stopwatch
      ..stop()
      ..reset();
    _recording = null;
    _lastError = null;
    _hasDetectedSpeech = false;
    _lastSpeechAt = null;
    _startedAt = null;
    _status = VoiceRecordingStatus.idle;
    _notifyIfActive();
  }

  // 새 음성 답변 녹음 시작
  Future<bool> start() async {
    if (_disposed ||
        _discardOperation != null ||
        _pendingRecorderStart != null ||
        _pendingRecorderStop != null ||
        _status == VoiceRecordingStatus.starting ||
        _status == VoiceRecordingStatus.recording ||
        _status == VoiceRecordingStatus.stopping) {
      return false;
    }

    final generation = ++_operationGeneration;
    _status = VoiceRecordingStatus.starting;
    _notifyIfActive();
    try {
      await beforeStart?.call();
    } on Object {
      // TTS 중단 실패가 아이의 녹음 시작까지 막아서는 안 된다.
    }
    if (!_isCurrentStart(generation)) return false;
    final permissionStatus = await permissionService?.request();
    if (!_isCurrentStart(generation)) return false;
    if (permissionStatus == MicrophonePermissionStatus.denied) {
      _status = VoiceRecordingStatus.permissionDenied;
      _notifyIfActive();
      return false;
    }
    if (permissionStatus == MicrophonePermissionStatus.permanentlyDenied) {
      _status = VoiceRecordingStatus.permissionPermanentlyDenied;
      _notifyIfActive();
      return false;
    }

    _recording = null;
    _lastError = null;
    _hasDetectedSpeech = false;
    _lastSpeechAt = null;
    _notifyIfActive();
    try {
      final pendingStart = _recorder.start();
      _pendingRecorderStart = pendingStart;
      await pendingStart;
      if (identical(_pendingRecorderStart, pendingStart)) {
        _pendingRecorderStart = null;
      }
      if (!_isCurrentStart(generation)) return false;
      _stopwatch
        ..reset()
        ..start();
      _startedAt = DateTime.now().toUtc();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        _notifyIfActive();
      });
      _amplitudeTimer = Timer.periodic(
        amplitudeSampleInterval,
        (_) => unawaited(_checkAmplitude()),
      );
      _status = VoiceRecordingStatus.recording;
      _notifyIfActive();
      return true;
    } on Object catch (error) {
      _pendingRecorderStart = null;
      if (!_isCurrentStart(generation)) return false;
      _lastError = error;
      _status = VoiceRecordingStatus.failed;
      _notifyIfActive();
      return false;
    }
  }

  // 영구 거부된 마이크 권한을 변경할 수 있도록 앱 설정 열기
  Future<bool> openPermissionSettings() async =>
      !_disposed && (await permissionService?.openSettings() ?? false);

  // 녹음을 종료하고 생성된 로컬 파일 정보 보관
  Future<VoiceRecording?> stop({
    VoiceRecordingCompletionReason reason =
        VoiceRecordingCompletionReason.manual,
  }) async {
    if (_disposed || _status != VoiceRecordingStatus.recording) return null;

    final generation = ++_operationGeneration;
    _status = VoiceRecordingStatus.stopping;
    _notifyIfActive();
    _ticker?.cancel();
    _ticker = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _stopwatch.stop();
    final duration = _stopwatch.elapsed;
    final endedAt = DateTime.now().toUtc();
    try {
      final pendingStop = _recorder.stop();
      _pendingRecorderStop = pendingStop;
      final path = await pendingStop;
      if (identical(_pendingRecorderStop, pendingStop)) {
        _pendingRecorderStop = null;
      }
      if (!_isCurrentOperation(generation) ||
          _status != VoiceRecordingStatus.stopping) {
        return null;
      }
      if (path == null || path.isEmpty) {
        throw StateError('Recorded file path is missing');
      }
      final result = VoiceRecording(
        filePath: path,
        duration: duration,
        startedAt: _startedAt ?? endedAt.subtract(duration),
        endedAt: endedAt,
        completionReason: reason,
      );
      _recording = result;
      _status = VoiceRecordingStatus.completed;
      _notifyIfActive();
      return result;
    } on Object catch (error) {
      _pendingRecorderStop = null;
      if (!_isCurrentOperation(generation)) return null;
      _lastError = error;
      _status = VoiceRecordingStatus.failed;
      _notifyIfActive();
      return null;
    }
  }

  // 앱 전환이나 통화 등으로 중단된 녹음 폐기
  Future<void> interrupt() async {
    if (_disposed) return;
    if (_discardOperation != null) {
      await _discardActiveRecording(VoiceRecordingStatus.interrupted);
      return;
    }
    if (_status == VoiceRecordingStatus.preparing) {
      _operationGeneration += 1;
      _status = VoiceRecordingStatus.interrupted;
      _notifyIfActive();
      return;
    }
    if (_status != VoiceRecordingStatus.recording &&
        _status != VoiceRecordingStatus.starting &&
        _status != VoiceRecordingStatus.stopping) {
      return;
    }
    await _discardActiveRecording(VoiceRecordingStatus.interrupted);
  }

  // 진행 중인 음성 답변을 폐기하고 대기 상태로 복귀
  Future<void> cancel() async {
    if (_disposed) return;
    if (_discardOperation != null) {
      await _discardActiveRecording(VoiceRecordingStatus.idle);
      return;
    }
    if (_status == VoiceRecordingStatus.preparing) {
      _operationGeneration += 1;
      _status = VoiceRecordingStatus.idle;
      _notifyIfActive();
      return;
    }
    if (_status != VoiceRecordingStatus.recording &&
        _status != VoiceRecordingStatus.starting &&
        _status != VoiceRecordingStatus.stopping) {
      return;
    }
    await _discardActiveRecording(VoiceRecordingStatus.idle);
  }

  // 음성이 없으면 녹음을 폐기하고 선택지 응답으로 전환
  Future<void> _checkAmplitude() async {
    if (_disposed ||
        _readingAmplitude ||
        _status != VoiceRecordingStatus.recording) {
      return;
    }
    final generation = _operationGeneration;
    _readingAmplitude = true;
    try {
      final amplitude = await _recorder.readAmplitude();
      if (!_isCurrentOperation(generation) ||
          _status != VoiceRecordingStatus.recording) {
        return;
      }
      final elapsed = _stopwatch.elapsed;
      if (amplitude >= speechThreshold) {
        _lastSpeechAt = elapsed;
        if (!_hasDetectedSpeech) {
          _hasDetectedSpeech = true;
          _notifyIfActive();
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
      if (!_isCurrentOperation(generation) ||
          _status != VoiceRecordingStatus.recording) {
        return;
      }
      _lastError = error;
      await _discardActiveRecording(VoiceRecordingStatus.failed);
    } finally {
      _readingAmplitude = false;
    }
  }

  Future<void> _moveToChoice() async {
    if (_disposed || _status != VoiceRecordingStatus.recording) return;
    await _discardActiveRecording(VoiceRecordingStatus.awaitingChoice);
  }

  Future<void> _discardActiveRecording(VoiceRecordingStatus nextStatus) {
    if (_discardOperation case final discard?) {
      _upgradeDiscardTarget(nextStatus);
      return discard;
    }
    _discardTargetStatus = nextStatus;
    _status = nextStatus;
    _recording = null;

    late final Future<void> operation;
    operation = _runDiscardActiveRecording().whenComplete(() {
      if (!identical(_discardOperation, operation)) return;
      _discardOperation = null;
      _discardTargetStatus = null;
      _notifyIfActive();
    });
    _discardOperation = operation;
    _notifyIfActive();
    return operation;
  }

  void _upgradeDiscardTarget(VoiceRecordingStatus nextStatus) {
    if (nextStatus != VoiceRecordingStatus.interrupted ||
        _discardTargetStatus == VoiceRecordingStatus.interrupted) {
      return;
    }
    _discardTargetStatus = nextStatus;
    _status = nextStatus;
    _notifyIfActive();
  }

  Future<void> _runDiscardActiveRecording() async {
    if (_disposed) return;
    final generation = ++_operationGeneration;
    final pendingStart = _pendingRecorderStart;
    final pendingStop = _pendingRecorderStop;
    _ticker?.cancel();
    _ticker = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _stopwatch
      ..stop()
      ..reset();
    var error = await _cancelRecorderSafely();
    await _awaitRecorderFuture(pendingStart);
    await _awaitRecorderFuture(pendingStop);
    if (pendingStart != null || pendingStop != null) {
      final postCompletionError = await _cancelRecorderSafely();
      error ??= postCompletionError;
    }
    if (!_isCurrentOperation(generation)) return;
    if (error != null) _lastError = error;
  }

  Future<void> _awaitRecorderFuture<T>(Future<T>? operation) async {
    if (operation == null) return;
    try {
      await operation;
    } on Object {
      // Recorder cleanup still needs to continue after a failed operation.
    }
  }

  Future<Object?> _cancelRecorderSafely() async {
    try {
      await _recorder.cancel();
      return null;
    } on Object catch (error) {
      return error;
    }
  }

  Future<void> _shutdownRecorder({
    required bool cancelActive,
    required Future<void>? pendingDiscard,
  }) async {
    final pendingStart = _pendingRecorderStart;
    final pendingStop = _pendingRecorderStop;
    if (pendingDiscard != null) {
      await pendingDiscard;
    } else {
      if (cancelActive) await _cancelRecorderSafely();
      await _awaitRecorderFuture(pendingStart);
      await _awaitRecorderFuture(pendingStop);
      if (pendingStart != null || pendingStop != null) {
        await _cancelRecorderSafely();
      }
    }
    try {
      await _recorder.dispose();
    } on Object {
      // Disposal is best effort and cannot be surfaced after ChangeNotifier dies.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    final pendingDiscard = _discardOperation;
    final cancelActive =
        _status == VoiceRecordingStatus.starting ||
        _status == VoiceRecordingStatus.recording ||
        _status == VoiceRecordingStatus.stopping;
    _disposed = true;
    _operationGeneration += 1;
    _ticker?.cancel();
    _ticker = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _stopwatch.stop();
    unawaited(
      _shutdownRecorder(
        cancelActive: cancelActive,
        pendingDiscard: pendingDiscard,
      ),
    );
    super.dispose();
  }
}
