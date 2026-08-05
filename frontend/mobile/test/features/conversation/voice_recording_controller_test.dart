import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('녹음 시작 전에 TTS 중단 경계를 기다린다', () async {
    final events = <String>[];
    final recorder = _FakeVoiceRecorder(onStart: () => events.add('record'));
    final controller = VoiceRecordingController(
      recorder,
      beforeStart: () async => events.add('tts-stop'),
    );

    await controller.start();

    expect(events, ['tts-stop', 'record']);
  });

  test('TTS 중단 실패는 녹음 시작을 막지 않는다', () async {
    final recorder = _FakeVoiceRecorder();
    final controller = VoiceRecordingController(
      recorder,
      beforeStart: () async => throw StateError('stop failed'),
    );

    expect(await controller.start(), isTrue);
    expect(recorder.startCount, 1);
    expect(controller.status, VoiceRecordingStatus.recording);
  });

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

  test('새 질문이 오면 이전 답변을 비우고 다시 녹음할 수 있다', () async {
    final recorder = _FakeVoiceRecorder();
    final controller = VoiceRecordingController(recorder);
    addTearDown(controller.dispose);

    await controller.start();
    await controller.stop();
    expect(controller.status, VoiceRecordingStatus.completed);
    expect(controller.recording, isNotNull);

    await controller.beginQuestion();
    expect(controller.status, VoiceRecordingStatus.idle);
    expect(controller.recording, isNull);
    expect(controller.hasDetectedSpeech, isFalse);

    await controller.start();
    expect(controller.status, VoiceRecordingStatus.recording);
    expect(recorder.startCount, 2);
  });

  testWidgets('질문 음성 재생 중에는 수동 말하기 버튼을 노출하지 않는다', (tester) async {
    final recorder = _FakeVoiceRecorder();
    final controller = VoiceRecordingController(recorder);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VoiceRecordingControl(controller: controller)),
      ),
    );

    controller.prepareForAutomaticStart();
    await tester.pump();

    expect(find.text('질문을 들려주고 있어요'), findsOneWidget);
    expect(find.text('말로 대답할래'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('voice-recording-toggle')),
          )
          .onPressed,
      isNull,
    );

    expect(await controller.start(), isTrue);
    await tester.pump();

    expect(controller.status, VoiceRecordingStatus.recording);
    expect(find.textContaining('녹음 끝내기'), findsOneWidget);
    await controller.cancel();
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
    // 발화 확정에는 연속 3샘플이 필요하다 — 한 샘플만 크면 잡음으로 본다.
    final recorder = _FakeVoiceRecorder(
      amplitude: -80,
      amplitudes: [-20, -20, -20, -80, -80, -80],
    );
    final controller = VoiceRecordingController(
      recorder,
      noSpeechTimeout: const Duration(milliseconds: 100),
      postSpeechSilenceTimeout: const Duration(milliseconds: 20),
      maximumDuration: const Duration(seconds: 1),
      amplitudeSampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(controller.status, VoiceRecordingStatus.completed);
    expect(controller.recording?.filePath, '/tmp/voice-answer.m4a');
    expect(recorder.stopCount, 1);
  });

  test('끊기는 잡음은 몇 번이 와도 발화로 확정하지 않고 선택지로 넘어간다', () async {
    // 실측(2026-08-05): 잡음 한 샘플이 발화로 확정돼 무음 타임아웃이 막히고, 잡음만 담긴
    // 녹음이 업로드돼 STT가 "구독, 좋아요 …"를 만들어 아이 답변으로 저장됐다.
    // 임계를 넘는 샘플과 넘지 않는 샘플이 번갈아 오는 동안에는 확정되지 않아야 한다.
    final recorder = _FakeVoiceRecorder(
      amplitude: -80,
      amplitudes: List<double>.generate(400, (i) => i.isEven ? -20 : -80),
    );
    final controller = VoiceRecordingController(
      recorder,
      noSpeechTimeout: const Duration(milliseconds: 50),
      amplitudeSampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(controller.hasDetectedSpeech, isFalse);
    expect(controller.status, VoiceRecordingStatus.awaitingChoice);
    expect(controller.shouldShowOptions, isTrue);
    expect(recorder.stopCount, 0);
  });

  test('연속 초과 샘플이 기준을 채우면 발화로 확정한다', () async {
    // 지속되는 말소리를 재현한다(큐 대신 고정값) — 타이머 지연에 결과가 흔들리지 않는다.
    final recorder = _FakeVoiceRecorder(amplitude: -20);
    final controller = VoiceRecordingController(
      recorder,
      noSpeechTimeout: const Duration(seconds: 5),
      postSpeechSilenceTimeout: const Duration(seconds: 5),
      maximumDuration: const Duration(seconds: 5),
      amplitudeSampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(controller.hasDetectedSpeech, isTrue);
    expect(controller.status, VoiceRecordingStatus.recording);
    await controller.cancel();
  });

  test('확정 기준 샘플 수는 조정할 수 있다', () async {
    final recorder = _FakeVoiceRecorder(amplitude: -20);
    final controller = VoiceRecordingController(
      recorder,
      speechConfirmSamples: 1,
      noSpeechTimeout: const Duration(seconds: 5),
      postSpeechSilenceTimeout: const Duration(seconds: 5),
      maximumDuration: const Duration(seconds: 5),
      amplitudeSampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(controller.hasDetectedSpeech, isTrue);
    await controller.cancel();
  });

  test('새 질문으로 넘어가면 연속 발화 샘플 계수를 초기화한다', () async {
    // 계수가 남으면 이전 질문의 잡음에 새 질문의 잡음 한 샘플이 붙어 발화로 확정된다.
    final recorder = _FakeVoiceRecorder(amplitude: -20);
    final controller = VoiceRecordingController(
      recorder,
      noSpeechTimeout: const Duration(milliseconds: 80),
      postSpeechSilenceTimeout: const Duration(seconds: 5),
      maximumDuration: const Duration(seconds: 5),
      amplitudeSampleInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(controller.hasDetectedSpeech, isTrue);

    await controller.beginQuestion();
    expect(controller.hasDetectedSpeech, isFalse);

    // 새 질문에서는 조용하고 잡음 한 샘플만 스친다 — 확정되면 계수가 남은 것이다.
    recorder.amplitude = -80;
    recorder.enqueue([-20]);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(controller.hasDetectedSpeech, isFalse);
    expect(controller.status, VoiceRecordingStatus.awaitingChoice);
  });

  test('최대 녹음 시간이 지나면 발화 파일을 자동으로 완료한다', () async {
    final recorder = _FakeVoiceRecorder(amplitude: -20);
    final controller = VoiceRecordingController(
      recorder,
      // 이 테스트의 관심사는 최대 시간이다. 기본 확정 기준(3샘플=30ms)이 maximumDuration과
      // 겹치면 '발화 확정'과 '시간 초과'가 같은 샘플에서 경쟁해 결과가 흔들린다 —
      // 확정을 첫 샘플로 당겨 경계를 분리한다.
      speechConfirmSamples: 1,
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
    expect(
      controller.recording?.completionReason,
      VoiceRecordingCompletionReason.maximumDuration,
    );
  });

  testWidgets('녹음 시작 실패 시 재시도 안내와 선택지를 제공한다', (tester) async {
    final recorder = _FakeVoiceRecorder(failOnStart: true);
    final controller = VoiceRecordingController(recorder);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VoiceRecordingControl(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('voice-recording-toggle')));
    await tester.pump();

    expect(controller.status, VoiceRecordingStatus.failed);
    expect(controller.shouldShowOptions, isTrue);
    expect(
      find.byKey(const ValueKey('voice-recording-failed')),
      findsOneWidget,
    );
  });

  test('앱 전환으로 중단된 녹음을 폐기하고 선택지를 제공한다', () async {
    final recorder = _FakeVoiceRecorder();
    final controller = VoiceRecordingController(recorder);
    addTearDown(controller.dispose);

    await controller.start();
    await controller.interrupt();

    expect(controller.status, VoiceRecordingStatus.interrupted);
    expect(controller.shouldShowOptions, isTrue);
    expect(controller.recording, isNull);
    expect(recorder.cancelCount, 1);
  });

  test('녹음 종료 실패 시 파일을 완료 처리하지 않는다', () async {
    final recorder = _FakeVoiceRecorder(failOnStop: true);
    final controller = VoiceRecordingController(recorder);
    addTearDown(controller.dispose);

    await controller.start();
    final recording = await controller.stop();

    expect(recording, isNull);
    expect(controller.status, VoiceRecordingStatus.failed);
    expect(controller.shouldShowOptions, isTrue);
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
  _FakeVoiceRecorder({
    this.amplitude = -20,
    List<double>? amplitudes,
    this.failOnStart = false,
    this.failOnStop = false,
    this.onStart,
  }) : _amplitudes = amplitudes ?? [];

  /// 큐가 비었을 때 계속 돌려줄 값. 테스트 중에 바꿀 수 있다(질문 사이 잡음 재현).
  double amplitude;
  final List<double> _amplitudes;

  /// 다음 샘플로 돌려줄 값을 큐 앞에 넣는다.
  void enqueue(List<double> values) => _amplitudes.addAll(values);
  final bool failOnStart;
  final bool failOnStop;
  final VoidCallback? onStart;
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;

  @override
  Future<void> start() async {
    startCount += 1;
    onStart?.call();
    if (failOnStart) throw StateError('start failed');
  }

  @override
  Future<double> readAmplitude() async =>
      _amplitudes.isEmpty ? amplitude : _amplitudes.removeAt(0);

  @override
  Future<String?> stop() async {
    stopCount += 1;
    if (failOnStop) throw StateError('stop failed');
    return '/tmp/voice-answer.m4a';
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  @override
  Future<void> dispose() async {}
}
