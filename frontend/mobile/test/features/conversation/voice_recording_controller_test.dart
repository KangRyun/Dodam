import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('녹음 시작과 종료 후 로컬 파일 정보를 보관한다', () async {
    final recorder = _FakeVoiceRecorder();
    final controller = VoiceRecordingController(recorder);
    addTearDown(controller.dispose);

    expect(await controller.start(), isTrue);
    expect(controller.status, VoiceRecordingStatus.recording);
    expect(recorder.startCount, 1);

    final recording = await controller.stop();

    expect(controller.status, VoiceRecordingStatus.completed);
    expect(recording?.filePath, '/tmp/voice-answer.m4a');
    expect(controller.recording, same(recording));
    expect(recorder.stopCount, 1);
  });

  testWidgets('녹음 버튼으로 시작하고 종료 결과를 전달한다', (tester) async {
    final recorder = _FakeVoiceRecorder();
    final controller = VoiceRecordingController(recorder);
    addTearDown(controller.dispose);
    VoiceRecording? completed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceRecordingControl(
            controller: controller,
            onCompleted: (recording) => completed = recording,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('voice-recording-toggle')));
    await tester.pump();
    expect(find.textContaining('녹음 끝내기'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-recording-toggle')));
    await tester.pump();
    expect(completed?.filePath, '/tmp/voice-answer.m4a');
    expect(
      find.byKey(const ValueKey('voice-recording-completed')),
      findsOneWidget,
    );
  });

  test('진행 중인 녹음을 취소하면 파일을 폐기하고 대기 상태로 돌아간다', () async {
    final recorder = _FakeVoiceRecorder();
    final controller = VoiceRecordingController(recorder);
    addTearDown(controller.dispose);

    await controller.start();
    await controller.cancel();

    expect(controller.status, VoiceRecordingStatus.idle);
    expect(controller.recording, isNull);
    expect(recorder.cancelCount, 1);
  });

  test('3초 동안 음성이 없으면 녹음을 폐기하고 선택지를 표시한다', () async {
    final recorder = _FakeVoiceRecorder(amplitude: -80);
    final controller = VoiceRecordingController(
      recorder,
      noSpeechTimeout: const Duration(milliseconds: 30),
      amplitudeSampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(controller.status, VoiceRecordingStatus.awaitingChoice);
    expect(controller.shouldShowOptions, isTrue);
    expect(recorder.cancelCount, 1);
  });

  test('음성이 감지되면 대기 시간이 지나도 선택지를 표시하지 않는다', () async {
    final recorder = _FakeVoiceRecorder(amplitude: -20);
    final controller = VoiceRecordingController(
      recorder,
      noSpeechTimeout: const Duration(milliseconds: 30),
      amplitudeSampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(controller.hasDetectedSpeech, isTrue);
    expect(controller.status, VoiceRecordingStatus.recording);
    expect(controller.shouldShowOptions, isFalse);
  });

  test('발화 후 침묵이 이어지면 녹음을 자동으로 완료한다', () async {
    final recorder = _FakeVoiceRecorder(amplitudes: [-20, -80, -80, -80]);
    final controller = VoiceRecordingController(
      recorder,
      noSpeechTimeout: const Duration(milliseconds: 100),
      postSpeechSilenceTimeout: const Duration(milliseconds: 20),
      maximumDuration: const Duration(seconds: 1),
      amplitudeSampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 70));

    expect(controller.status, VoiceRecordingStatus.completed);
    expect(controller.recording?.filePath, '/tmp/voice-answer.m4a');
    expect(recorder.stopCount, 1);
  });

  test('최대 녹음 시간이 지나면 발화 파일을 자동으로 완료한다', () async {
    final recorder = _FakeVoiceRecorder(amplitude: -20);
    final controller = VoiceRecordingController(
      recorder,
      noSpeechTimeout: const Duration(seconds: 1),
      postSpeechSilenceTimeout: const Duration(seconds: 1),
      maximumDuration: const Duration(milliseconds: 30),
      amplitudeSampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(controller.status, VoiceRecordingStatus.completed);
    expect(recorder.stopCount, 1);
  });

  testWidgets('마이크 권한 거부 시 다시 허용할 수 있는 안내를 표시한다', (tester) async {
    final recorder = _FakeVoiceRecorder();
    final permission = _FakeMicrophonePermissionService(
      MicrophonePermissionStatus.denied,
    );
    final controller = VoiceRecordingController(
      recorder,
      permissionService: permission,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VoiceRecordingControl(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('voice-recording-toggle')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('microphone-permission-denied')),
      findsOneWidget,
    );
    expect(recorder.startCount, 0);
  });

  testWidgets('마이크 권한 영구 거부 시 기기 설정 이동을 제공한다', (tester) async {
    final recorder = _FakeVoiceRecorder();
    final permission = _FakeMicrophonePermissionService(
      MicrophonePermissionStatus.permanentlyDenied,
    );
    final controller = VoiceRecordingController(
      recorder,
      permissionService: permission,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VoiceRecordingControl(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('voice-recording-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('microphone-open-settings')));

    expect(
      find.byKey(const ValueKey('microphone-permission-permanently-denied')),
      findsOneWidget,
    );
    expect(permission.openSettingsCount, 1);
    expect(recorder.startCount, 0);
  });
}

final class _FakeMicrophonePermissionService
    implements MicrophonePermissionService {
  _FakeMicrophonePermissionService(this.status);

  final MicrophonePermissionStatus status;
  int openSettingsCount = 0;

  @override
  Future<MicrophonePermissionStatus> request() async => status;

  @override
  Future<bool> openSettings() async {
    openSettingsCount += 1;
    return true;
  }
}

final class _FakeVoiceRecorder implements VoiceRecorder {
  _FakeVoiceRecorder({this.amplitude = -20, List<double>? amplitudes})
    : _amplitudes = amplitudes ?? [];

  final double amplitude;
  final List<double> _amplitudes;
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<double> readAmplitude() async =>
      _amplitudes.isEmpty ? amplitude : _amplitudes.removeAt(0);

  @override
  Future<String?> stop() async {
    stopCount += 1;
    return '/tmp/voice-answer.m4a';
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  @override
  Future<void> dispose() async {}
}
