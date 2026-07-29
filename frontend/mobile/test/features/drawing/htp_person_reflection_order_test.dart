import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PERSON 감정 화면이 확정 계약 순서대로 서버를 호출하는지 고정한다.
///
///   HTP Reflection 저장 → steps/next → complete
///
/// 백엔드는 PERSON 세션이 `REFLECTION` 단계일 때만 Reflection을 받고
/// `steps/next`가 그 세션을 `COMPLETED`로 바꾸므로, 순서가 뒤바뀌면 Reflection이
/// 영구히 저장되지 않는다.
const _personContext = DrawingActivityContextDto(
  activityKind: 'HTP',
  htpAssessmentId: 91,
  htpStatus: 'IN_PROGRESS',
  stepOrder: 3,
  drawingSubject: 'PERSON',
);

Future<void> _pumpPersonEmotionScreen(
  WidgetTester tester, {
  required _RecordingHtpRepository repository,
  String inputMethod = 'UPLOAD',
}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name != AppRoutes.activityComplete('3')) return null;
        final arguments = settings.arguments! as ActivityCompleteRouteArguments;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              Scaffold(body: Text('activity-complete-${arguments.sessionId}')),
        );
      },
      home: EmotionSelectScreen(
        childId: '3',
        sessionId: 44,
        drawingRepository: repository,
        conversationAlreadyEnded: true,
        activityContext: _personContext,
        inputMethod: inputMethod,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pickEmotionAndSubmit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
  await tester.pumpAndSettle();
  await _submitAgain(tester);
}

Future<void> _submitAgain(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('emotion-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('PERSON은 Reflection → steps/next → complete 순서로 호출한다', (
    tester,
  ) async {
    final repository = _RecordingHtpRepository();

    await _pumpPersonEmotionScreen(tester, repository: repository);
    await _pickEmotionAndSubmit(tester);

    expect(repository.callLog, [
      'saveHtpReflection(91)',
      'stepsNext(UPLOAD)',
      'complete(91)',
    ]);
    // HTP 흐름에서 Drawing Session Reflection은 절대 호출하지 않는다.
    expect(repository.drawingSessionReflectionCalls, 0);
    expect(find.text('activity-complete-44'), findsOneWidget);
  });

  testWidgets('steps/next에 세션의 실제 inputMethod를 전달한다(CANVAS 하드코딩 없음)', (
    tester,
  ) async {
    final repository = _RecordingHtpRepository();

    await _pumpPersonEmotionScreen(
      tester,
      repository: repository,
      inputMethod: 'UPLOAD',
    );
    await _pickEmotionAndSubmit(tester);

    expect(repository.stepInputMethods, ['UPLOAD']);
  });

  testWidgets('Reflection이 실패하면 steps/next와 complete를 호출하지 않는다', (
    tester,
  ) async {
    final repository = _RecordingHtpRepository(failReflectionOnce: true);

    await _pumpPersonEmotionScreen(tester, repository: repository);
    await _pickEmotionAndSubmit(tester);

    expect(repository.callLog, ['saveHtpReflection(91)']);
    expect(repository.stepCalls, 0);
    expect(repository.completeCalls, 0);
    // 완료 화면으로 넘어가지 않고 감정 화면에 머문다.
    expect(find.text('activity-complete-44'), findsNothing);
  });

  testWidgets('complete만 실패한 재시도는 Reflection·steps/next를 다시 부르지 않는다', (
    tester,
  ) async {
    final repository = _RecordingHtpRepository(failCompleteOnce: true);

    await _pumpPersonEmotionScreen(tester, repository: repository);
    await _pickEmotionAndSubmit(tester);

    // 1차: Reflection·steps/next는 성공했고 complete만 실패했다.
    expect(repository.reflectionCalls, 1);
    expect(repository.stepCalls, 1);
    expect(repository.completeCalls, 1);
    expect(find.text('activity-complete-44'), findsNothing);

    // 재시도 — complete만 다시 나가야 한다.
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pumpAndSettle();

    expect(repository.reflectionCalls, 1);
    expect(repository.stepCalls, 1);
    expect(repository.completeCalls, 2);
    // complete 재시도는 같은 Key를 재사용한다.
    expect(repository.completeKeys.first, repository.completeKeys.last);
    expect(find.text('activity-complete-44'), findsOneWidget);
  });
}

final class _RecordingHtpRepository
    implements DrawingRepository, HtpDrawingRepository {
  _RecordingHtpRepository({
    this.failReflectionOnce = false,
    this.failCompleteOnce = false,
  });

  bool failReflectionOnce;
  bool failCompleteOnce;

  final List<String> callLog = [];
  final List<String> stepInputMethods = [];
  final List<String> stepKeys = [];
  final List<String> completeKeys = [];
  int reflectionCalls = 0;
  int stepCalls = 0;
  int completeCalls = 0;
  int drawingSessionReflectionCalls = 0;

  @override
  Future<void> saveHtpReflection(
    int assessmentId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    reflectionCalls += 1;
    callLog.add('saveHtpReflection($assessmentId)');
    if (failReflectionOnce) {
      failReflectionOnce = false;
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
  }

  @override
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
    required String idempotencyKey,
  }) async {
    // Reflection보다 먼저 불리면 계약 위반이다.
    if (reflectionCalls == 0) {
      throw StateError('steps/next가 HTP Reflection보다 먼저 호출됐다.');
    }
    stepCalls += 1;
    stepInputMethods.add(inputMethod);
    stepKeys.add(idempotencyKey);
    callLog.add('stepsNext($inputMethod)');
    return HtpAssessmentDto(
      htpAssessmentId: assessmentId,
      status: 'IN_PROGRESS',
      expiresAt: '2026-08-01T00:00:00Z',
      currentStep: const HtpAssessmentStepDto(
        stepOrder: 3,
        drawingSubject: 'PERSON',
        drawingSessionId: 44,
        sessionStatus: 'COMPLETED',
        currentStage: 'COMPLETED',
      ),
      allStepsCompleted: true,
    );
  }

  @override
  Future<void> completeHtpAssessment(
    int assessmentId, {
    required String idempotencyKey,
  }) async {
    completeCalls += 1;
    completeKeys.add(idempotencyKey);
    callLog.add('complete($assessmentId)');
    if (failCompleteOnce) {
      failCompleteOnce = false;
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
  }

  /// HTP 흐름에서 호출되면 안 되는 세션 단위 Reflection.
  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    drawingSessionReflectionCalls += 1;
    throw StateError('HTP 흐름에서 Drawing Session Reflection을 부르면 안 된다.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
