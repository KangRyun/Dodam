import 'dart:async';

import 'package:dodam/app/router/app_router.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child_mode/presentation/screens/child_mode_screens.dart';
import 'package:dodam/features/child_mode/presentation/widgets/activity_guide_dialog.dart';
import 'package:dodam/features/drawing/application/drawing_session_start_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/screens/input_method_select_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _child = ChildSummaryDto(
  childId: 7,
  nickname: '도담',
  birthDate: '2020-01-01',
  age: 6,
  profileImageUrl: null,
  preferredCharacter: null,
  questionDifficulty: 'EASY',
  tutorialStatus: 'DONE',
  relationshipType: 'PARENT',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

const _artDiary = DrawingTypeDto(
  drawingTypeId: 5,
  code: 'ART_DIARY',
  name: '그림일기',
  activityCategory: 'GENERAL',
  selectableBy: 'BOTH',
  recommendedAgeMin: 4,
  recommendedAgeMax: 12,
  guideText: '오늘 있었던 일을 그림으로 그려 볼까?',
  displayOrder: 1,
);

const _secondType = DrawingTypeDto(
  drawingTypeId: 9,
  code: 'HTP',
  name: '집·나무·사람 그림',
  activityCategory: 'ASSESSMENT',
  selectableBy: 'BOTH',
  recommendedAgeMin: null,
  recommendedAgeMax: null,
  guideText: null,
  displayOrder: 2,
);

Widget _wrap(Widget home) => MaterialApp(
  home: home,
  onGenerateRoute: (settings) {
    if (settings.name == AppRoutes.drawingInputMethod('7')) {
      final arguments = settings.arguments! as InputMethodSelectRouteArguments;
      return MaterialPageRoute<DrawingSessionResolution>(
        settings: settings,
        builder: (_) => InputMethodSelectScreen(
          childId: arguments.childId,
          drawingTypeId: arguments.drawingTypeId,
          title: arguments.title,
          description: arguments.description,
          icon: arguments.icon,
          accentColor: arguments.accentColor,
          repository: arguments.repository,
        ),
      );
    }
    if (settings.name != AppRoutes.drawing('7')) return null;
    final arguments = settings.arguments! as DrawingRouteArguments;
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (routeContext) => Scaffold(
        body: Column(
          children: [
            Text(
              'drawing-session-${arguments.sessionId}-resume-${arguments.resumeConversation}'
              '-auto-${arguments.autoRestoreDraft}',
            ),
            TextButton(
              key: const ValueKey('leave-drawing'),
              onPressed: () => Navigator.of(routeContext).pop(),
              child: const Text('나가기'),
            ),
          ],
        ),
      ),
    );
  },
);

void main() {
  testWidgets('지원하는 그림 유형마다 카드가 표시된다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_secondType, _artDiary],
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-9')), findsOneWidget);
    expect(find.text('그림일기'), findsOneWidget);
    expect(find.text('집·나무·사람 그림'), findsOneWidget);
    // 활동 유형과 무관한 기존 "지난 그림 보기" 카드는 그대로 유지된다.
    expect(find.text('지난 그림 보기'), findsOneWidget);
  });

  testWidgets('그림 유형을 불러오는 동안 로딩 상태를 보여준다', (tester) async {
    final completer = Completer<ApiPage<DrawingTypeDto>>();
    final repository = _FakeDrawingRepository(typesCompleter: completer);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pump();

    expect(find.byType(AppLoadingView), findsOneWidget);

    completer.complete(
      const ApiPage(
        content: [_artDiary],
        page: 0,
        size: 1,
        totalElements: 1,
        totalPages: 1,
        hasNext: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-5')), findsOneWidget);
  });

  testWidgets('그림 유형을 불러오지 못하면 오류와 다시 시도를 보여준다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary],
      getTypesFailure: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
      failGetTypesOnce: true,
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorView), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-5')), findsNothing);

    await tester.ensureVisible(find.text('다시 시도'));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-5')), findsOneWidget);
  });

  testWidgets('지원하는 그림 유형이 없으면 빈 상태를 보여준다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const []);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppEmptyView), findsOneWidget);
  });

  testWidgets('그림일기 외 활동도 같은 공통 안내 팝업을 안내 문구만 바꿔 재사용한다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_secondType],
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('activity-9')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-guide-start')), findsOneWidget);
    expect(find.text('집·나무·사람 그림'), findsWidgets);
    // guideText가 없는 유형은 아동 친화적인 임시 문구로 대체된다.
    expect(find.text('그리고 싶은 것을 자유롭게 그려 보자!'), findsWidgets);
  });

  testWidgets('카드를 탭하면 해당 활동 안내 팝업이 표시된다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('activity-5')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-guide-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-guide-cancel')), findsOneWidget);
    expect(find.text('그림일기'), findsWidgets);
    expect(find.text('오늘 있었던 일을 그림으로 그려 볼까?'), findsWidgets);
    expect(repository.createCalls, 0);
  });

  testWidgets('취소를 누르면 세션을 만들지 않고 홈에 남는다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-5')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('activity-guide-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
    expect(find.byKey(const ValueKey('activity-5')), findsOneWidget);
    expect(repository.createCalls, 0);
    // 안내 팝업을 띄우기 전에 이어 그리기 대상이 있는지 한 번 확인한다.
    expect(repository.getActiveSessionCalls, 1);
  });

  testWidgets('스크림을 탭해도 세션을 만들지 않고 홈에 남는다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-5')));
    await tester.pumpAndSettle();

    // 팝업 바깥(스크림)을 탭해 취소와 같은 효과를 낸다.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
    expect(repository.createCalls, 0);
  });

  testWidgets('그림일기 시작하기는 CANVAS 세션을 만들고 바로 이동한다', (tester) async {
    final repository = _FakeDrawingRepository(drawingTypes: const [_artDiary]);

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-5')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('activity-guide-start')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(repository.lastCreateRequest?.childId, 7);
    expect(repository.lastCreateRequest?.drawingTypeId, 5);
    expect(repository.lastCreateRequest?.inputMethod, 'CANVAS');
    expect(
      find.text('drawing-session-900-resume-false-auto-false'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('input-method-photo')), findsNothing);
  });

  testWidgets('기존 활성 세션이 있으면 그대로 재개하고 새 세션을 만들지 않는다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary],
      activeSession: const ActiveDrawingSessionDto(
        drawingSessionId: 321,
        childId: 7,
        drawingType: DrawingTypeSummaryDto(
          drawingTypeId: 5,
          code: 'ART_DIARY',
          name: '그림일기',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'CONVERSING',
        startedAt: '2026-07-26T01:00:00Z',
        latestDraft: null,
      ),
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    // 진행 중 활동 확인은 활동 종류를 선택하기 전에 한 번만 수행한다.
    expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
    expect(find.text('이어 그리기'), findsOneWidget);
    await tester.tap(find.text('이어 그리기'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 0);
    expect(
      find.text('drawing-session-321-resume-true-auto-true'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('leave-drawing')));
    await tester.pumpAndSettle();

    // 같은 화면으로 돌아와도 이미 처리한 진입 팝업은 다시 열지 않는다.
    expect(find.text('이어 그리기'), findsNothing);
    expect(find.text('새로 그리기'), findsNothing);
  });

  testWidgets('저장된 초안이 없는 활성 세션도 재개와 새 활동을 선택한다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary],
      activeSession: const ActiveDrawingSessionDto(
        drawingSessionId: 555,
        childId: 7,
        drawingType: DrawingTypeSummaryDto(
          drawingTypeId: 5,
          code: 'ART_DIARY',
          name: '그림일기',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
        startedAt: '2026-07-26T01:00:00Z',
        latestDraft: null,
      ),
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-guide-start')), findsNothing);
    expect(find.text('이어 그리기'), findsOneWidget);
    expect(repository.createCalls, 0);

    await tester.tap(find.text('이어 그리기'));
    await tester.pumpAndSettle();

    expect(
      find.text('drawing-session-555-resume-false-auto-true'),
      findsOneWidget,
    );
  });

  testWidgets('새로 그리기를 고른 뒤 그림일기를 선택하면 새 캔버스로 이동한다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary, _secondType],
      activeSession: const ActiveDrawingSessionDto(
        drawingSessionId: 555,
        childId: 7,
        drawingType: DrawingTypeSummaryDto(
          drawingTypeId: 9,
          code: 'HTP',
          name: '집·나무·사람 그림',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
        startedAt: '2026-07-26T01:00:00Z',
        latestDraft: null,
      ),
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('새로 그리기'), findsOneWidget);
    await tester.tap(find.text('새로 그리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-guide-start')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(
      repository.lastCreateRequest?.drawingTypeId,
      _artDiary.drawingTypeId,
    );
    expect(repository.lastCreateRequest?.inputMethod, 'CANVAS');
    expect(repository.lastCreateRequest?.replaceActive, isTrue);
    expect(
      find.text('drawing-session-900-resume-false-auto-false'),
      findsOneWidget,
    );
  });

  testWidgets('새로 그리기를 고른 뒤 HTP와 캔버스를 선택하면 HOUSE 캔버스로 이동한다', (tester) async {
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary, _secondType],
      activeSession: const ActiveDrawingSessionDto(
        drawingSessionId: 555,
        childId: 7,
        drawingType: DrawingTypeSummaryDto(
          drawingTypeId: 5,
          code: 'ART_DIARY',
          name: '그림일기',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
        startedAt: '2026-07-26T01:00:00Z',
        latestDraft: null,
      ),
    );

    await tester.pumpWidget(
      _wrap(ChildModeHomeScreen(child: _child, drawingRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('새로 그리기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('activity-9')));
    await tester.tap(find.byKey(const ValueKey('activity-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-guide-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
    await tester.pumpAndSettle();

    expect(repository.htpStartCalls, 1);
    expect(repository.lastHtpRequest?.inputMethod, 'CANVAS');
    expect(repository.lastHtpRequest?.replaceActive, isTrue);
    expect(
      find.text('drawing-session-901-resume-false-auto-false'),
      findsOneWidget,
    );
  });

  testWidgets('좁은 화면과 2배 텍스트에서도 오버플로가 없다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeDrawingRepository(
      drawingTypes: const [_artDiary, _secondType],
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2.0),
        ),
        child: _wrap(
          ChildModeHomeScreen(child: _child, drawingRepository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('activity-5')));
    await tester.tap(find.byKey(const ValueKey('activity-5')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('안내 팝업도 좁은 화면과 2배 텍스트에서 오버플로가 없다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completer = Completer<DrawingSessionResolution>();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2.0),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showActivityGuideDialog<DrawingSessionResolution>(
                      context: context,
                      title: '그림일기',
                      description: '오늘 있었던 일을 아주 길게 자세히 적어 보면서 그림으로도 함께 그려 볼까?',
                      icon: Icons.menu_book_rounded,
                      accentColor: AppColors.tangerine,
                      onStart: () => completer.future,
                    ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('activity-guide-start')), findsOneWidget);
  });
}

final class _FakeDrawingRepository
    implements DrawingRepository, HtpDrawingRepository {
  _FakeDrawingRepository({
    this.drawingTypes = const [],
    this.activeSession,
    this.getTypesFailure,
    this.failGetTypesOnce = false,
    this.typesCompleter,
  });

  final List<DrawingTypeDto> drawingTypes;
  final ActiveDrawingSessionDto? activeSession;
  final Object? getTypesFailure;
  bool failGetTypesOnce;
  final Completer<ApiPage<DrawingTypeDto>>? typesCompleter;

  int getDrawingTypesCalls = 0;
  int getActiveSessionCalls = 0;
  int createCalls = 0;
  int htpStartCalls = 0;
  CreateDrawingSessionRequestDto? lastCreateRequest;
  StartHtpAssessmentRequestDto? lastHtpRequest;

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) async {
    getDrawingTypesCalls += 1;
    if (typesCompleter case final completer?) return completer.future;
    if (getTypesFailure case final failure? when failGetTypesOnce) {
      failGetTypesOnce = false;
      throw failure;
    }
    return ApiPage(
      content: drawingTypes,
      page: 0,
      size: drawingTypes.length,
      totalElements: drawingTypes.length,
      totalPages: drawingTypes.isEmpty ? 0 : 1,
      hasNext: false,
    );
  }

  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async {
    getActiveSessionCalls += 1;
    return activeSession;
  }

  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async {
    createCalls += 1;
    lastCreateRequest = request;
    return DrawingSessionDto.fromCreateJson({
      'drawingSessionId': 900,
      'childId': request.childId,
      'drawingType': {
        'drawingTypeId': request.drawingTypeId,
        'code': 'ART_DIARY',
        'name': '그림일기',
      },
      'inputMethod': request.inputMethod,
      'title': null,
      'sessionStatus': 'DRAWING',
      'currentStage': 'DRAWING',
      'selectedEmotions': null,
      'expressedEmotionText': null,
      'startedAt': request.clientStartedAt,
      'completedAt': null,
      'conversation': null,
      'latestAnalysis': null,
      'assets': [],
    });
  }

  @override
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  ) async {
    htpStartCalls += 1;
    lastHtpRequest = request;
    return const HtpAssessmentDto(
      htpAssessmentId: 91,
      status: 'IN_PROGRESS',
      expiresAt: '2026-07-30T01:00:00Z',
      currentStep: HtpAssessmentStepDto(
        stepOrder: 1,
        drawingSubject: 'HOUSE',
        drawingSessionId: 901,
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
      ),
      allStepsCompleted: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
