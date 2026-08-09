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
    this.speechConfirmSamples = 3,
    this.beforeStart,
  });

  final VoiceRecorder _recorder;
  final MicrophonePermissionService? permissionService;
  final Duration noSpeechTimeout;
  final Duration postSpeechSilenceTimeout;
  final Duration maximumDuration;
  final Duration amplitudeSampleInterval;
  final double speechThreshold;

  /// 발화로 확정하기까지 필요한 연속 초과 샘플 수.
  ///
  /// 한 샘플만 임계를 넘어도 발화로 확정하면 에어컨·문 닫는 소리·형제 목소리 같은
  /// 순간 잡음이 "아이가 말했다"가 된다. 그러면 무음 타임아웃(선택지 노출) 경로가
  /// 막히고, 잡음만 담긴 녹음이 업로드돼 STT가 학습 데이터 정형구를 만들어낸다
  /// (2026-08-05 실측: 무음 녹음이 "구독, 좋아요 …"로 저장됨).
  /// 기본 3샘플 = 600ms 연속 — 말소리는 이보다 길고, 순간 잡음은 이보다 짧다.
  final int speechConfirmSamples;
  final Future<void> Function()? beforeStart;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  Timer? _amplitudeTimer;
  bool _readingAmplitude = false;
  bool _disposed = false;
  Future<void>? _cancelFuture;

  /// 취소할 때마다 오르는 세대 번호.
  ///
  /// recorder 는 비동기다 — 취소 시점에 이미 떠난 stop() 결과가 나중에 돌아온다.
  /// 그 결과를 그대로 받으면 아이가 고른 답 위에 무음 녹음이 덮인다.
  int _generation = 0;

  VoiceRecordingStatus _status = VoiceRecordingStatus.idle;
  VoiceRecording? _recording;
  Object? _lastError;
  bool _hasDetectedSpeech = false;
  int _consecutiveSpeechSamples = 0;
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
      _status == VoiceRecordingStatus.stopping;

  // 질문 음성을 들려주는 동안 수동 녹음 버튼이 먼저 노출되지 않게 한다.
  void prepareForAutomaticStart() {
    if (_disposed || _status != VoiceRecordingStatus.idle) return;
    _status = VoiceRecordingStatus.preparing;
    notifyListeners();
  }

  // 새 질문에서는 이전 질문의 녹음 결과와 오류 상태를 재사용하지 않는다.
  Future<void> beginQuestion() async {
    if (_disposed) return;
    if (_status == VoiceRecordingStatus.starting ||
        _status == VoiceRecordingStatus.recording) {
      await cancel();
    }
    if (_disposed) return;
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
    _consecutiveSpeechSamples = 0;
    _lastSpeechAt = null;
    _startedAt = null;
    _status = VoiceRecordingStatus.idle;
    notifyListeners();
  }

  // 새 음성 답변 녹음 시작
  Future<bool> start() async {
    if (_disposed ||
        _status == VoiceRecordingStatus.starting ||
        _status == VoiceRecordingStatus.recording ||
        _status == VoiceRecordingStatus.stopping) {
      return false;
    }

    _status = VoiceRecordingStatus.starting;
    notifyListeners();
    try {
      await beforeStart?.call();
    } on Object {
      // TTS 중단 실패가 아이의 녹음 시작까지 막아서는 안 된다.
    }
    if (_disposed || _status != VoiceRecordingStatus.starting) return false;
    final permissionStatus = await permissionService?.request();
    if (_disposed || _status != VoiceRecordingStatus.starting) return false;
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
    _consecutiveSpeechSamples = 0;
    _lastSpeechAt = null;
    notifyListeners();
    try {
      await _recorder.start();
      if (_disposed) return false;
      if (_status != VoiceRecordingStatus.starting) {
        await _cancelRecorder();
        return false;
      }
      _stopwatch
        ..reset()
        ..start();
      _startedAt = DateTime.now().toUtc();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed) notifyListeners();
      });
      _amplitudeTimer = Timer.periodic(
        amplitudeSampleInterval,
        (_) => unawaited(_checkAmplitude()),
      );
      _status = VoiceRecordingStatus.recording;
      notifyListeners();
      return true;
    } on Object catch (error) {
      if (_disposed) return false;
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
    if (_disposed || _status != VoiceRecordingStatus.recording) return null;

    final generation = _generation;
    _status = VoiceRecordingStatus.stopping;
    notifyListeners();
    _ticker?.cancel();
    _ticker = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _stopwatch.stop();
    final duration = _stopwatch.elapsed;
    final endedAt = DateTime.now().toUtc();
    try {
      final path = await _recorder.stop();
      // 멈추는 사이 취소됐다. 아이가 보기를 골랐다는 뜻이라 이 녹음은 답이 아니다.
      if (_disposed || generation != _generation) return null;
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
      notifyListeners();
      return result;
    } on Object catch (error) {
      if (_disposed || generation != _generation) return null;
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

  /// 진행 중인 음성 답변을 폐기하고 대기 상태로 복귀한다.
  ///
  /// **`stopping`·`completed` 에서도 폐기한다.** 예전에는 `recording`·`starting`
  /// 에서만 취소돼서, 아이가 보기를 고르는 사이 이미 멈춘 녹음이 그대로 남아 답으로
  /// 올라갔다. 취소는 "지금 만들던 답을 버린다"는 뜻이라 어느 단계에서든 들어야 한다.
  ///
  /// 세대(generation)를 올려 **늦게 도착한 recorder 결과를 무시**한다. `stop()` 이
  /// 이미 진행 중이면 그 결과는 이 취소 뒤에 도착하는데, 세대가 달라 반영되지 않는다.
  Future<void> cancel() async {
    if (_disposed || _status == VoiceRecordingStatus.idle) return;
    _generation += 1;
    final generation = _generation;

    _ticker?.cancel();
    _ticker = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _stopwatch
      ..stop()
      ..reset();
    Object? cancelError;
    try {
      await _cancelRecorder();
    } on Object catch (error) {
      cancelError = error;
    }
    if (_disposed || generation != _generation) return;
    if (cancelError != null) _lastError = cancelError;
    _recording = null;
    _status = VoiceRecordingStatus.idle;
    notifyListeners();
  }

  // 음성이 없으면 녹음을 폐기하고 선택지 응답으로 전환
  Future<void> _checkAmplitude() async {
    if (_disposed ||
        _readingAmplitude ||
        _status != VoiceRecordingStatus.recording) {
      return;
    }
    _readingAmplitude = true;
    try {
      final amplitude = await _recorder.readAmplitude();
      if (_disposed || _status != VoiceRecordingStatus.recording) return;
      final elapsed = _stopwatch.elapsed;
      if (amplitude >= speechThreshold) {
        _consecutiveSpeechSamples += 1;
        // 연속 초과가 기준을 채운 뒤에만 '말했다'로 본다. 그 전 샘플은 잡음일 수 있어
        // 침묵 종료 판정(_lastSpeechAt)에도 쓰지 않는다 — 쓰면 잡음이 녹음을 늘린다.
        if (_consecutiveSpeechSamples >= speechConfirmSamples) {
          _lastSpeechAt = elapsed;
          if (!_hasDetectedSpeech) {
            _hasDetectedSpeech = true;
            notifyListeners();
          }
        }
      } else {
        _consecutiveSpeechSamples = 0;
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
      if (_disposed) return;
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
    if (_disposed) return;
    final generation = _generation;
    _ticker?.cancel();
    _ticker = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _stopwatch
      ..stop()
      ..reset();
    Object? cancelError;
    try {
      await _cancelRecorder();
    } on Object catch (error) {
      cancelError = error;
    }
    if (_disposed || generation != _generation) return;
    if (cancelError != null) _lastError = cancelError;
    _recording = null;
    _status = nextStatus;
    notifyListeners();
  }

  Future<void> _cancelRecorder() {
    final pending = _cancelFuture;
    if (pending != null) return pending;

    late final Future<void> cancellation;
    cancellation = Future<void>.sync(_recorder.cancel).whenComplete(() {
      if (identical(_cancelFuture, cancellation)) _cancelFuture = null;
    });
    _cancelFuture = cancellation;
    return cancellation;
  }

  Future<void> _disposeRecorder() async {
    try {
      if (_status == VoiceRecordingStatus.starting ||
          isRecording ||
          _status == VoiceRecordingStatus.stopping ||
          _cancelFuture != null) {
        await _cancelRecorder();
      }
    } on Object {
      // dispose 이후에는 정리 실패를 상태로 전파할 수 없다.
    } finally {
      try {
        await _recorder.dispose();
      } on Object {
        // ChangeNotifier 수명 종료 후의 recorder 오류는 안전하게 종료한다.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _ticker?.cancel();
    _amplitudeTimer?.cancel();
    unawaited(_disposeRecorder());
    super.dispose();
  }
}
