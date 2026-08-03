import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('사이드바 "프로필 전환"은 프로필 선택 화면으로 이동한다', (tester) async {
    // 보호자 홈은 태블릿 사이드바 레이아웃이라 태블릿 크기로 검증한다.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();
    // 홈 대시보드가 떠 있어야 한다(아이 자동 선택 상태).
    expect(find.byKey(const ValueKey('child-list-success')), findsOneWidget);

    // 사이드바의 "프로필 전환" → 프로필 선택 화면. 로그아웃은 그 화면에서 한다.
    await tester.tap(find.byKey(const ValueKey('guardian-switch-profile')));
    await tester.pumpAndSettle();

    expect(find.text('안녕하세요! 누구로 시작할까요?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-selection-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('logout-action')), findsOneWidget);
  });

  test('보호자 선택 상태를 초기화한다', () async {
    final controller = GuardianChildController(
      _FakeChildRepository(children: _children),
    );
    await controller.loadChildren();
    controller.selectChild(_children.first);

    expect(controller.selectedChildId, _children.first.childId);
    controller.clearSelection();

    expect(controller.selectedChild, isNull);
    controller.dispose();
  });

  test('로그아웃하면 아동 목록과 선택 및 등록 상태를 모두 초기화한다', () async {
    final controller = GuardianChildController(
      _FakeChildRepository(children: _children),
    );
    await controller.loadChildren();
    controller.selectChild(_children.first);

    controller.clear();

    expect(controller.status, ChildListStatus.idle);
    expect(controller.children, isEmpty);
    expect(controller.selectedChild, isNull);
    expect(controller.registrationStatus, ChildRegistrationStatus.idle);
    expect(controller.registrationError, isNull);
    controller.dispose();
  });

  testWidgets('Child 목록 Loading 상태를 표시한다', (tester) async {
    final completer = Completer<List<ChildSummaryDto>>();
    final repository = _FakeChildRepository(pending: completer);

    await tester.pumpWidget(DodamApp(childRepository: repository));

    expect(find.byKey(const ValueKey('child-list-loading')), findsOneWidget);
    completer.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('Child 목록 Error에서 Retry하면 다시 조회한다', (tester) async {
    final repository = _FakeChildRepository(error: StateError('network'));
    await tester.pumpWidget(DodamApp(childRepository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-list-error')), findsOneWidget);
    repository
      ..error = null
      ..children = _children;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repository.getChildrenCalls, 2);
    expect(find.byKey(const ValueKey('child-list-success')), findsOneWidget);
  });

  testWidgets('Child 목록 Empty 상태를 표시한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: const [])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-list-empty')), findsOneWidget);
  });

  testWidgets('Child 목록 Success와 실제 DTO 정보를 표시한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-list-success')), findsOneWidget);
    expect(find.text('도담이'), findsWidgets);
    expect(find.text('봄이'), findsOneWidget);
    expect(find.textContaining('활동 12회'), findsOneWidget);
  });

  testWidgets('선택된 childId를 유지해 해당 아동 모드로 진입한다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository();
    await _pumpActivitySelect(
      tester,
      drawingRepository,
      childKey: const ValueKey('child-7'),
    );

    // 보호자 HTP 버튼은 활동 종류 선택을 생략하고 입력 방식부터 보여준다.
    await _pumpUntil(tester, find.byKey(const ValueKey('input-method-canvas')));
    await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
    await tester.pumpAndSettle();

    // 선택한 아동의 HTP 준비 정보를 유지한 채 아동 홈으로 진입한다.
    expect(find.byKey(const ValueKey('draw-entry')), findsOneWidget);
  });

  testWidgets('보호자 HTP 버튼은 입력 방식 선택 후 아동 홈과 HTP 캔버스로 연결된다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository();
    await _pumpActivitySelect(tester, drawingRepository);

    expect(find.text('집·나무·사람 그림'), findsOneWidget);
    expect(find.text('어떤 활동을 해볼까요?'), findsNothing);
    expect(find.byKey(const ValueKey('input-method-photo')), findsNothing);
    expect(find.byKey(const ValueKey('input-method-camera')), findsNothing);
    expect(find.byKey(const ValueKey('input-method-gallery')), findsNothing);
    expect(drawingRepository.htpStartCalls, 0);
    expect(drawingRepository.createCalls, 0);
    expect(drawingRepository.uploadCalls, 0);
    expect(drawingRepository.completeSessionId, isNull);
    await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draw-entry')), findsOneWidget);
    await _tapAfterScroll(tester, const ValueKey('draw-entry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
  });

  testWidgets('보호자 HTP는 flag가 켜져 있으면 사진 CTA와 촬영 안내를 연다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository();
    await _pumpActivitySelect(
      tester,
      drawingRepository,
      htpPhotoUploadEnabled: true,
    );

    await _pumpUntil(tester, find.byKey(const ValueKey('input-method-photo')));
    expect(find.byKey(const ValueKey('input-method-photo')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('input-method-photo')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('input-method-camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('input-method-gallery')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('input-method-camera')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('camera-guidance-capture')),
      findsOneWidget,
    );
    expect(drawingRepository.htpStartCalls, 0);
    expect(drawingRepository.createCalls, 0);
    expect(drawingRepository.uploadCalls, 0);
    expect(drawingRepository.completeSessionId, isNull);
  });

  testWidgets('활성 그림 세션이 있으면 새로 만들지 않고 기존 sessionId로 재개한다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository(activeSessionId: 812);
    await _pumpChildHome(tester, drawingRepository);

    // 진입 시 활성 세션이 있으면 활동 카드 탭 없이도 '이어/새로' 선택
    // 다이얼로그가 자동으로 뜬다(_resolveEntry).
    await _pumpUntil(tester, find.text('이어 그리기'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('이어 그리기'));
    await _pumpUntil(tester, find.byKey(const ValueKey('drawing-canvas')));

    expect(drawingRepository.createCalls, 0);
    // 461 카드 목록을 채우려고 홈이 이미 그림 유형을 한 번 조회했다(활성 세션
    // 존재 여부와 무관). resolveSession 내부는 활성 세션이 있으면 이 조회를
    // 다시 하지 않는다 — 그건 drawing_session_start_controller_test.dart가
    // 별도로 검증한다.
    expect(drawingRepository.getTypesChildId, 3);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
  });

  testWidgets('임시 저장 그림이 있으면 이어 그리기와 새로 그리기를 선택한다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository(
      activeSessionId: 812,
      activeHasDraft: true,
    );
    await _pumpChildHome(tester, drawingRepository);

    // 진입 시 활성 세션(임시 저장본)이 있으면 활동 카드 탭 없이도 '이어/새로'
    // 선택 다이얼로그가 자동으로 뜬다(_resolveEntry). 다이얼로그 등장 애니메이션이
    // 끝나 버튼이 탭 가능해질 때까지 기다린다.
    await _pumpUntil(tester, find.text('이어 그리기'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('그리던 그림이 있어요'), findsOneWidget);
    expect(find.text('이어 그리기'), findsOneWidget);
    expect(find.text('새로 그리기'), findsOneWidget);

    await tester.tap(find.text('이어 그리기'));
    await _pumpUntil(tester, find.byKey(const ValueKey('drawing-canvas')));

    expect(drawingRepository.deletedSessionIds, isEmpty);
    expect(drawingRepository.createCalls, 0);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
  });

  testWidgets('새로 그리기는 선택한 활동을 교체 옵션으로 바로 생성한다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository(
      activeSessionId: 812,
      activeHasDraft: true,
    );
    await _pumpActivitySelect(tester, drawingRepository);

    // 활동 선택 화면 진입 시 활성 세션이 있으면 '이어/새로' 다이얼로그가 뜬다.
    // '새로 그리기'를 고르면 기존 세션을 교체하도록 표시하고 HTP 입력 방식을 보여준다.
    await _pumpUntil(tester, find.text('새로 그리기'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('새로 그리기'));
    await tester.pumpAndSettle();

    await _pumpUntil(tester, find.byKey(const ValueKey('input-method-canvas')));
    await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
    await tester.pumpAndSettle();
    await _tapAfterScroll(tester, const ValueKey('draw-entry'));
    await _pumpUntil(tester, find.byKey(const ValueKey('drawing-canvas')));

    expect(drawingRepository.deletedSessionIds, isEmpty);
    expect(drawingRepository.htpStartCalls, 1);
    expect(drawingRepository.lastHtpRequest?.inputMethod, 'CANVAS');
    expect(drawingRepository.lastHtpRequest?.replaceActive, isTrue);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
  });

  testWidgets('실제 앱 진입 흐름에서 선택한 아동의 HTP 세션을 생성한다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository(
      sessionId: 731,
      completionStage: 'REFLECTION',
    );
    await tester.pumpWidget(
      DodamApp(
        childRepository: _FakeChildRepository(children: _children),
        drawingRepository: drawingRepository,
        drawingCompletionSnapshotProvider: () async => _png,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('child-3')));
    await tester.pump();
    await _startHtpFromHome(tester);

    await _pumpUntil(tester, find.byKey(const ValueKey('input-method-canvas')));
    await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
    await tester.pumpAndSettle();
    await _tapAfterScroll(tester, const ValueKey('draw-entry'));
    await tester.pumpAndSettle();

    expect(drawingRepository.getTypesChildId, 3);
    expect(drawingRepository.htpStartCalls, 1);
    expect(drawingRepository.lastHtpRequest?.childId, 3);
    expect(drawingRepository.lastHtpRequest?.inputMethod, 'CANVAS');
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);

    expect(drawingRepository.lastHtpRequest?.replaceActive, isFalse);
  });

  testWidgets('세션 생성 실패 시 Drawing으로 이동하지 않고 다시 시도할 수 있다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository(
      createError: StateError('create failed'),
    );
    await _pumpActivitySelect(tester, drawingRepository);

    await _pumpUntil(tester, find.byKey(const ValueKey('input-method-canvas')));
    await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
    await tester.pumpAndSettle();

    // 실패 시 Drawing으로 이동하지 않고 활동 선택 화면에 머문다.
    expect(drawingRepository.htpStartCalls, 1);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsNothing);
    expect(
      find.byKey(const ValueKey('input-method-canvas-error')),
      findsOneWidget,
    );

    // 오류 안내가 사라진 뒤 같은 활동으로 다시 시도할 수 있다.
    await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
    await tester.pumpAndSettle();

    expect(drawingRepository.htpStartCalls, 2);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsNothing);
  });

  testWidgets('활동 시작 연속 탭은 DrawingSession을 중복 생성하지 않는다', (tester) async {
    final pending = Completer<HtpAssessmentDto>();
    final drawingRepository = _TrackingDrawingRepository(pending: pending);
    await _pumpActivitySelect(tester, drawingRepository);

    await _pumpUntil(tester, find.byKey(const ValueKey('input-method-canvas')));
    // 입력 방식 카드를 연속으로 두 번 눌러도 세션은 한 번만 생성된다.
    final canvasChoice = find.byKey(const ValueKey('input-method-canvas'));
    await tester.tap(canvasChoice);
    await tester.tap(canvasChoice);
    await tester.pump();

    expect(drawingRepository.htpStartCalls, 1);

    pending.complete(drawingRepository.htpAssessment());
    await tester.pumpAndSettle();

    // 중복 생성 없이 아동 홈으로 진입한다.
    expect(drawingRepository.htpStartCalls, 1);
    expect(find.byKey(const ValueKey('draw-entry')), findsOneWidget);
  });

  testWidgets('아동 모드에는 보호자 전용 요약과 리포트 정보가 노출되지 않는다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('child-3')));
    await tester.pump();
    await _startHtpFromHome(tester);
    await tester.pumpAndSettle();

    expect(find.text('월간 활동 요약'), findsNothing);
    expect(find.text('관찰 리포트'), findsNothing);
    expect(find.textContaining('위험'), findsNothing);
    expect(find.textContaining('분석 상세'), findsNothing);
  });

  testWidgets('childId가 없는 직접 아동 모드 접근은 보호한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(
        childRepository: _FakeChildRepository(children: _children),
        initialRoute: AppRoutes.childModeHome('7'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('선택된 아동이 없어요'), findsOneWidget);
    expect(find.text('봄이, 오늘은 무엇을 그려 볼까?'), findsNothing);
  });

  // 회원 탈퇴 안내처럼 "아이가 없다"는 단정이 위험한 화면이 쓰는 값이다.
  // 실패·미조회를 0으로 뭉개면 서버가 실제로 아이를 삭제하는데도 없다고 안내한다.
  test('아동 수는 목록 조회가 확정된 뒤에만 알려준다', () async {
    final repository = _FakeChildRepository(children: _children);
    final controller = GuardianChildController(repository);
    addTearDown(controller.dispose);

    expect(controller.confirmedChildCount, isNull, reason: '조회 전에는 확정된 수가 없다');

    await controller.loadChildren();
    expect(controller.confirmedChildCount, _children.length);

    repository.children = const [];
    await controller.loadChildren();
    expect(controller.confirmedChildCount, 0, reason: '실제로 0건임을 확인한 경우에만 0이다');

    repository.error = StateError('offline');
    await controller.loadChildren();
    expect(controller.status, ChildListStatus.error);
    expect(
      controller.confirmedChildCount,
      isNull,
      reason: '조회 실패는 "아이 0명"이 아니다',
    );

    controller.clear();
    expect(controller.confirmedChildCount, isNull);
  });
}

Future<void> _tapAfterScroll(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.ensureVisible(target);
  await tester.tap(target);
}

/// 보호자 홈 CTA를 눌러 HTP 소개 팝업을 연 뒤 "시작하기"로 활동 흐름에 진입한다
/// (S15P11B209-462). 소개 팝업이 활동 흐름 앞단에 끼면서 진입 경로가 이 단계를
/// 반드시 거치게 됐다.
Future<void> _startHtpFromHome(WidgetTester tester) async {
  await _tapAfterScroll(tester, const ValueKey('start-child-mode'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('htp-intro-start')));
}

/// 활동 선택 화면의 "다음" 버튼을 눌러 아동 홈으로 넘어간다.
/// 보호자 홈에서 아동을 골라 활동 선택 화면까지 진입한다.
Future<void> _pumpActivitySelect(
  WidgetTester tester,
  DrawingRepository drawingRepository, {
  Key childKey = const ValueKey('child-3'),
  bool htpPhotoUploadEnabled = false,
}) async {
  await tester.pumpWidget(
    DodamApp(
      childRepository: _FakeChildRepository(children: _children),
      drawingRepository: drawingRepository,
      htpPhotoUploadEnabled: htpPhotoUploadEnabled,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(childKey));
  await tester.pump();
  await _startHtpFromHome(tester);
  // 활동 선택 화면은 진입 확인 로딩과 이어/새로 다이얼로그 애니메이션이 계속
  // 돌아 pumpAndSettle이 멎지 않으므로 제한 프레임만 진행한다.
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 지속 애니메이션이 있는 화면은 pumpAndSettle이 멎지 않으므로, 대상 위젯이
/// 나타날 때까지만 제한 프레임을 진행한다.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 80,
}) async {
  for (var i = 0; i < maxFrames && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpChildHome(
  WidgetTester tester,
  DrawingRepository drawingRepository,
) => _pumpActivitySelect(tester, drawingRepository);

const _children = [
  ChildSummaryDto(
    childId: 3,
    nickname: '도담이',
    birthDate: '2019-03-14',
    age: 7,
    profileImageUrl: null,
    preferredCharacter: 'BEAR',
    questionDifficulty: 'PRESCHOOL',
    tutorialStatus: 'COMPLETED',
    relationshipType: 'MOTHER',
    recentActivity: ChildRecentActivityDto(
      lastActivityAt: '2026-07-20T08:15:00Z',
      totalActivityCount: 12,
    ),
  ),
  ChildSummaryDto(
    childId: 7,
    nickname: '봄이',
    birthDate: '2016-11-02',
    age: 9,
    profileImageUrl: null,
    preferredCharacter: 'RABBIT',
    questionDifficulty: 'ELEMENTARY',
    tutorialStatus: 'NOT_STARTED',
    relationshipType: 'MOTHER',
    recentActivity: ChildRecentActivityDto(
      lastActivityAt: null,
      totalActivityCount: 0,
    ),
  ),
];

const _png = BinaryUploadDto(
  bytes: [137, 80, 78, 71],
  fileName: 'final.png',
  mimeType: 'image/png',
);

final class _FakeChildRepository implements ChildRepository {
  _FakeChildRepository({this.children = const [], this.error, this.pending});

  List<ChildSummaryDto> children;
  Object? error;
  Completer<List<ChildSummaryDto>>? pending;
  int getChildrenCalls = 0;

  @override
  Future<List<ChildSummaryDto>> getChildren() async {
    getChildrenCalls += 1;
    if (pending case final pending?) return pending.future;
    if (error case final error?) throw error;
    return children;
  }

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) =>
      throw UnimplementedError();
  @override
  Future<void> deleteChild(int childId) => throw UnimplementedError();
  @override
  Future<ChildDetailDto> getChild(int childId) => throw UnimplementedError();
  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) async {
    final status = children
        .singleWhere((child) => child.childId == childId)
        .tutorialStatus;
    return TutorialProgressDto(
      childId: childId,
      tutorialStatus: status,
      lastStep: status == 'COMPLETED' ? 'COMPLETE' : null,
      completedAt: status == 'COMPLETED' ? '2026-07-20T08:15:00Z' : null,
      updatedAt: '2026-07-20T08:15:00Z',
    );
  }

  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) async => TutorialProgressDto(
    childId: childId,
    tutorialStatus: request.tutorialStatus,
    lastStep: request.lastStep,
    completedAt: request.tutorialStatus == 'COMPLETED'
        ? '2026-07-20T08:15:00Z'
        : null,
    updatedAt: '2026-07-20T08:15:00Z',
  );
}

final class _TrackingDrawingRepository
    implements
        DrawingRepository,
        DrawingSessionDiscarder,
        HtpDrawingRepository {
  _TrackingDrawingRepository({
    this.sessionId = 731,
    this.activeSessionId,
    this.activeHasDraft = false,
    this.completionStage = 'CONVERSING',
    this.createError,
    this.pending,
  });

  final int sessionId;
  final int? activeSessionId;
  final bool activeHasDraft;
  final String completionStage;
  final Object? createError;
  final Completer<HtpAssessmentDto>? pending;
  int createCalls = 0;
  int htpStartCalls = 0;
  int uploadCalls = 0;
  int? getTypesChildId;
  int? completeSessionId;
  int? reflectionSessionId;
  bool activityCompletionAccepted = false;
  final List<int> deletedSessionIds = [];
  CreateDrawingSessionRequestDto? createRequest;
  StartHtpAssessmentRequestDto? lastHtpRequest;

  HtpAssessmentDto htpAssessment() => HtpAssessmentDto(
    htpAssessmentId: 91,
    status: 'IN_PROGRESS',
    expiresAt: '2026-07-30T01:00:00Z',
    currentStep: HtpAssessmentStepDto(
      stepOrder: 1,
      drawingSubject: 'HOUSE',
      drawingSessionId: sessionId,
      sessionStatus: 'IN_PROGRESS',
      currentStage: 'DRAWING',
    ),
    allStepsCompleted: false,
  );

  @override
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  ) async {
    htpStartCalls += 1;
    lastHtpRequest = request;
    if (createError case final error?) throw error;
    return pending?.future ?? htpAssessment();
  }

  @override
  Future<HtpAssessmentDto> getHtpAssessment(int assessmentId) async =>
      htpAssessment();

  @override
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
    required String idempotencyKey,
  }) async => htpAssessment();

  @override
  Future<void> saveHtpReflection(
    int assessmentId,
    SaveDrawingReflectionRequestDto request,
  ) async {}

  @override
  Future<void> completeHtpAssessment(
    int assessmentId, {
    required String idempotencyKey,
  }) async {}

  DrawingSessionDto session() => DrawingSessionDto.fromCreateJson({
    'drawingSessionId': sessionId,
    'childId': 3,
    'drawingType': {'drawingTypeId': 77, 'code': 'FREE', 'name': '자유화'},
    'inputMethod': 'CANVAS',
    'title': null,
    'sessionStatus': activityCompletionAccepted ? 'COMPLETED' : 'DRAWING',
    'currentStage': activityCompletionAccepted ? 'COMPLETED' : 'DRAWING',
    'selectedEmotions': null,
    'expressedEmotionText': null,
    'startedAt': '2026-07-22T00:00:00Z',
    'completedAt': activityCompletionAccepted ? '2026-07-22T00:10:00Z' : null,
    'conversation': null,
    'latestAnalysis': null,
    'assets': <Object>[],
  });

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) async {
    getTypesChildId = childId;
    return const ApiPage(
      content: [
        DrawingTypeDto(
          drawingTypeId: 88,
          code: 'HTP',
          name: '집·나무·사람 그림',
          activityCategory: 'HTP',
          selectableBy: 'GUARDIAN_ONLY',
          recommendedAgeMin: null,
          recommendedAgeMax: null,
          guideText: '집, 나무, 사람을 순서대로 그려 보세요.',
          displayOrder: 1,
        ),
        DrawingTypeDto(
          drawingTypeId: 77,
          code: 'ART_DIARY',
          name: '그림일기',
          activityCategory: 'GENERAL',
          selectableBy: 'GUARDIAN_OR_CHILD',
          recommendedAgeMin: null,
          recommendedAgeMax: null,
          guideText: '오늘 있었던 일을 그림으로 그려 보세요.',
          displayOrder: 2,
        ),
      ],
      page: 0,
      size: 2,
      totalElements: 2,
      totalPages: 1,
      hasNext: false,
    );
  }

  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async {
    createCalls += 1;
    createRequest = request;
    if (createError case final error?) throw error;
    return session();
  }

  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async => null;
  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async {
    final id = activeSessionId;
    if (id == null) return null;
    return ActiveDrawingSessionDto(
      drawingSessionId: id,
      childId: childId,
      drawingType: const DrawingTypeSummaryDto(
        drawingTypeId: 88,
        code: 'HTP',
        name: '집·나무·사람 그림',
      ),
      inputMethod: 'CANVAS',
      sessionStatus: 'DRAWING',
      currentStage: 'DRAWING',
      startedAt: '2026-07-22T00:00:00Z',
      latestDraft: activeHasDraft
          ? const ActiveDrawingDraftDto(
              drawingAssetId: 301,
              assetVersion: 2,
              lastEventSequence: 18,
              savedAt: '2026-07-29T01:00:00Z',
            )
          : null,
    );
  }

  @override
  Future<Uint8List> downloadDraftPreview(String previewUrl) =>
      throw UnimplementedError();

  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async => StrokeBatchResponseDto(
    batchId: 1,
    batchSequence: request.batchSequence,
    acceptedEventCount: request.events.length,
    lastEventSequence: request.lastEventSequence,
    receivedAt: '2026-07-22T00:00:00Z',
  );

  @override
  Future<DrawingStageCompleteResponseDto> completeDrawingStage(
    int sessionId, {
    required BinaryUploadDto finalImage,
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) async {
    completeSessionId = sessionId;
    return DrawingStageCompleteResponseDto.fromJson({
      'drawingSessionId': sessionId,
      'finalAssetId': 900,
      'sessionStatus': 'IN_PROGRESS',
      'currentStage': completionStage,
      'analysis': {
        'analysisId': 901,
        'analysisType': 'INTERMEDIATE',
        'status': 'SUCCEEDED',
      },
      'nextAction': 'SELECT_EMOTION',
    });
  }

  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) async => reflectionSessionId = sessionId;

  @override
  Future<DrawingCompletionResponseDto> completeActivity(
    int sessionId, {
    required CompleteActivityRequestDto request,
    required String idempotencyKey,
  }) async {
    activityCompletionAccepted = true;
    return DrawingCompletionResponseDto(
      drawingSessionId: sessionId,
      sessionStatus: 'IN_PROGRESS',
      currentStage: 'REPORTING',
      analysisId: 902,
      analysisStatus: 'PENDING',
      reportId: 903,
      reportStatus: 'GENERATING',
    );
  }

  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState, {
    required String idempotencyKey,
  }) async => DraftSaveResponseDto(
    drawingAssetId: 1,
    assetVersion: 1,
    lastEventSequence: canvasState.lastEventSequence,
    savedAt: '2026-07-22T00:00:00Z',
    expiresAt: null,
  );

  @override
  Future<void> deleteDraft(int sessionId) async {}
  @override
  Future<void> deleteSession(int sessionId) async {
    deletedSessionIds.add(sessionId);
  }

  @override
  Future<DrawingSessionDto> getSession(int sessionId) async => session();
  @override
  Future<ObjectDetectionResponseDto> requestObjectDetection(
    int sessionId,
    ObjectDetectionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    required UploadDrawingImageMetadataDto metadata,
    required String idempotencyKey,
  }) {
    uploadCalls += 1;
    throw StateError('이 테스트에서는 사진 업로드를 호출하면 안 된다.');
  }
}
