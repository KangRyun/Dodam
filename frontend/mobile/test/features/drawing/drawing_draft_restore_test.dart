import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dodam/app/router/app_router.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/application/drawing_draft_restore_controller.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sessionId가 없으면 Draft API를 호출하지 않고 바로 그릴 수 있다', () async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(
      sessionId: null,
      repository: repository,
    );
    final controller = DrawingDraftRestoreController(
      sessionId: null,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();

    expect(repository.getDraftCalls, 0);
    expect(controller.status, DrawingDraftRestoreStatus.unavailable);
    expect(controller.canDraw, isTrue);
  });

  test('Draft 없음은 오류가 아닌 새 Canvas 상태로 처리한다', () async {
    final repository = _DraftRepository(scenario: _Scenario.absent);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.status, DrawingDraftRestoreStatus.noDraft);
    expect(controller.canDraw, isTrue);
  });

  test('빈 Draft 응답도 오류가 아닌 새 Canvas 상태로 처리한다', () async {
    final repository = _DraftRepository(scenario: _Scenario.empty);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.status, DrawingDraftRestoreStatus.noDraft);
    expect(controller.canDraw, isTrue);
  });

  test('Draft 조회 실패와 이미지 실패를 구분하고 재시도할 수 있다', () async {
    final repository = _DraftRepository(scenario: _Scenario.failure);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
      imageProviderFactory: (_) => MemoryImage(Uint8List.fromList([0])),
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.status, DrawingDraftRestoreStatus.queryFailed);

    repository.scenario = _Scenario.found;
    await controller.load();
    await controller.continueDrawing();
    controller.markImageFailed();
    expect(controller.status, DrawingDraftRestoreStatus.imageFailed);

    await controller.retryImage();
    expect(controller.status, DrawingDraftRestoreStatus.loadingImage);
  });

  test('이어 그리기는 Repository에서 인증된 이미지 bytes를 내려받는다', () async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();
    await controller.continueDrawing();

    expect(repository.downloadDraftPreviewCalls, 1);
    expect(repository.downloadedPreviewUrl, _asset.fileUrl);
    expect(controller.backgroundImage, isA<MemoryImage>());
    expect(controller.status, DrawingDraftRestoreStatus.loadingImage);
  });

  test('진입 화면에서 이어 그리기를 선택하면 Draft를 다시 묻지 않고 자동 복원한다', () async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load(autoRestore: true);

    expect(repository.getDraftCalls, 1);
    expect(repository.downloadDraftPreviewCalls, 1);
    expect(controller.backgroundImage, isA<MemoryImage>());
    expect(controller.status, DrawingDraftRestoreStatus.loadingImage);
  });

  test('복구 뒤 event와 batch 시퀀스를 모두 이어받는다', () async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();
    final events = sync.recordStroke(_stroke(), const Size(100, 100));
    await sync.flushEvents();

    expect(events.first.seq, 1106);
    expect(events.last.seq, 1107);
    // batchSequence도 Draft의 lastEventSequence(1105) 뒤인 1106부터 시작해야 이미
    // 저장된 batchSequence=1과 충돌(DRAWING_409_019)하지 않는다.
    expect(repository.lastBatch?.batchSequence, 1106);
    expect(repository.lastBatch?.firstEventSequence, events.last.seq);
    expect(repository.lastBatch?.lastEventSequence, events.last.seq);
    expect(sync.journal.events, hasLength(2));
    expect(sync.journal.lastEventSequence, events.last.seq);
  });

  test('서버 시퀀스가 null이면 기존 로컬 기본값을 유지한다', () async {
    final repository = _DraftRepository(nullSequences: true);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();
    final events = sync.recordStroke(_stroke(), const Size(100, 100));
    await sync.flushEvents();

    expect(events.first.seq, 1);
    expect(repository.lastBatch?.batchSequence, 1);
  });

  test('같은 Draft metadata 요청은 하나로 합쳐진다', () async {
    final pending = Completer<DraftRecoveryDto?>();
    final repository = _DraftRepository(pendingDraft: pending);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    final first = controller.load();
    final second = controller.load();
    await Future<void>.delayed(Duration.zero);

    expect(repository.getDraftCalls, 1);
    pending.complete(_draftRecovery);
    await Future.wait([first, second]);
    expect(controller.status, DrawingDraftRestoreStatus.found);
  });

  test('새로 시작한 뒤 늦은 Draft metadata 응답은 화면을 덮지 않는다', () async {
    final pending = Completer<DraftRecoveryDto?>();
    final repository = _DraftRepository(pendingDraft: pending);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    final loading = controller.load();
    await Future<void>.delayed(Duration.zero);
    controller.startNewDrawing();
    pending.complete(_draftRecovery);
    await loading;

    expect(controller.status, DrawingDraftRestoreStatus.newDrawing);
    expect(controller.draft, isNull);
    expect(controller.backgroundImage, isNull);
  });

  test('새로 시작한 뒤 늦은 preview 응답은 화면을 덮지 않는다', () async {
    final pendingPreview = Completer<Uint8List>();
    final repository = _DraftRepository(pendingPreview: pendingPreview);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);
    await controller.load();

    final first = controller.continueDrawing();
    final duplicate = controller.continueDrawing();
    await Future<void>.delayed(Duration.zero);
    expect(repository.downloadDraftPreviewCalls, 1);

    controller.startNewDrawing();
    pendingPreview.complete(_validPng);
    await Future.wait([first, duplicate]);

    expect(controller.status, DrawingDraftRestoreStatus.newDrawing);
    expect(controller.backgroundImage, isNull);
  });

  test('dispose 뒤 늦은 metadata 응답은 상태 알림을 발생시키지 않는다', () async {
    final pending = Completer<DraftRecoveryDto?>();
    final repository = _DraftRepository(pendingDraft: pending);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    var notifications = 0;
    controller.addListener(() => notifications += 1);
    final loading = controller.load();
    await Future<void>.delayed(Duration.zero);
    final notificationsAtDispose = notifications;

    controller.dispose();
    pending.complete(_draftRecovery);
    await loading;

    expect(notifications, notificationsAtDispose);
  });

  test('403 Draft 조회 실패는 영구 오류로 분류해 retry를 숨긴다', () async {
    final repository = _DraftRepository(
      scenario: _Scenario.failure,
      failure: ApiResponseFailure(statusCode: 403, error: null),
    );
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.status, DrawingDraftRestoreStatus.queryFailed);
    expect(controller.failure, isA<ApiResponseFailure>());
    expect(controller.canRetry, isFalse);
  });

  testWidgets('복구 이미지를 배경으로 표시하고 새 Stroke와 Undo를 분리한다', (tester) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final restore = await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
    );

    expect(find.text('그리던 그림이 있어요'), findsOneWidget);
    expect(find.text('이어서 그릴까요?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('draft-primary-action')));
    restore.markImageLoaded();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('draft-background-image')),
      findsOneWidget,
    );
    expect(find.text('그리던 그림이 있어요'), findsNothing);
    expect(_canvas(tester).strokes, isEmpty);

    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(24, 18));
    await gesture.up();
    await tester.pump();
    expect(_canvas(tester).strokes, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();
    expect(_canvas(tester).strokes, isEmpty);
    expect(
      find.byKey(const ValueKey('draft-background-image')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('새로 시작은 서버 Draft를 삭제하지 않고 빈 Canvas를 연다', (tester) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    await _pumpScreen(tester, repository: repository, sync: sync);

    await tester.tap(find.byKey(const ValueKey('draft-start-new')));
    await tester.pump();

    expect(repository.deleteDraftCalls, 0);
    expect(find.byKey(const ValueKey('draft-background-image')), findsNothing);
    expect(_canvas(tester).strokes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('앞 화면에서 이어 그리기를 선택하면 캔버스 선택창을 다시 표시하지 않는다', (tester) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
      autoRestoreDraft: true,
    );

    expect(find.text('그리던 그림이 있어요'), findsNothing);
    expect(find.text('이어서 그리기'), findsNothing);
    expect(repository.downloadDraftPreviewCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('이어 그리기 Draft를 조회하는 동안 도담이 로딩 화면을 표시한다', (tester) async {
    final pendingDraft = Completer<DraftRecoveryDto?>();
    final repository = _DraftRepository(pendingDraft: pendingDraft);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);

    await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
      autoRestoreDraft: true,
    );

    expect(
      find.byKey(const ValueKey('draft-restore-loading-character')),
      findsOneWidget,
    );
    expect(find.text('그리던 그림을 확인하고 있어요'), findsOneWidget);
    expect(_canvas(tester).inputEnabled, isFalse);

    pendingDraft.complete(null);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('주제 선택 뒤 새 활동은 Draft를 조회하지 않고 빈 캔버스를 연다', (tester) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
      startFresh: true,
    );

    expect(repository.getDraftCalls, 0);
    expect(find.text('그리던 그림이 있어요'), findsNothing);
    expect(find.byKey(const ValueKey('draft-background-image')), findsNothing);
    expect(_canvas(tester).strokes, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('복구 배경과 새 Stroke는 같은 snapshot 경계 안에서 저장된다', (tester) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final restore = await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
    );
    await tester.tap(find.byKey(const ValueKey('draft-primary-action')));
    restore.markImageLoaded();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(24, 18));
    await gesture.up();
    await tester.pump();
    await tester.runAsync(sync.saveDraftNow);

    expect(repository.savedImage?.mimeType, 'image/png');
    expect(repository.savedImage?.bytes, isNotEmpty);
    expect(repository.savedLastEventSequence, 1107);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('draft-background-image')),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('복원된 Draft만 있어도 완료 버튼을 활성화한다', (tester) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final restore = await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
      autoRestoreDraft: true,
    );

    for (var attempt = 0; attempt < 10; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 20));
      if (restore.backgroundImage != null) break;
    }
    restore.markImageLoaded();
    await tester.pump();

    // 완료 버튼은 사이드 패널이 아니라 크레용 툴바에 있다(S15P11B209-805).
    final button = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('drawing-complete')),
        matching: find.byType(InkWell),
      ),
    );
    expect(button.onTap, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('다른 화면 비율에서도 raster와 새 stroke를 같은 snapshot에 합성한다', (
    tester,
  ) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final restore = await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
      size: const Size(500, 900),
    );
    await tester.tap(find.byKey(const ValueKey('draft-primary-action')));
    await tester.runAsync(
      () => _waitFor(() => restore.backgroundImage != null),
    );
    expect(restore.backgroundImage, isNotNull);
    restore.markImageLoaded();
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('drawing-canvas')));
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(20, 16));
    await gesture.up();
    await tester.pump();
    await tester.runAsync(sync.saveDraftNow);

    expect(
      find.byKey(const ValueKey('draft-background-image')),
      findsOneWidget,
    );
    expect(_canvas(tester).strokes, hasLength(1));
    expect(repository.savedImage?.bytes, isNotEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('Draft 선택 overlay는 작은 화면과 textScale 2.0에서 overflow가 없다', (
    tester,
  ) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
      size: const Size(420, 760),
      textScaler: const TextScaler.linear(2),
    );

    expect(find.byKey(const ValueKey('draft-start-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('draft-primary-action')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('paused에서 batch와 Draft를 저장하고 resumed 뒤 autosave를 재개한다', (
    tester,
  ) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      policy: const DrawingSyncPolicy(
        flushInterval: Duration(hours: 1),
        autosaveInterval: Duration(milliseconds: 100),
      ),
    );
    await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
      startFresh: true,
    );
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final first = await tester.startGesture(center);
    await first.moveBy(const Offset(24, 18));
    await first.up();
    await tester.pump();

    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _waitFor(() => repository.saveDraftCalls == 1);
    });
    await tester.pumpAndSettle();

    expect(repository.strokeBatchCalls, 1);
    expect(repository.saveDraftCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final second = await tester.startGesture(center + const Offset(30, 20));
    await second.moveBy(const Offset(24, 18));
    await second.up();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(() => _waitFor(() => repository.saveDraftCalls == 2));
    await tester.pumpAndSettle();

    expect(repository.saveDraftCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('시스템 뒤로 가기는 batch와 Draft 저장 뒤 한 번만 pop한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    addTearDown(sync.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _CountingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('이전 화면')),
      ),
    );
    final routeResult = navigatorKey.currentState!.push<DrawingRouteResult>(
      MaterialPageRoute<DrawingRouteResult>(
        builder: (_) => DrawingScreen(
          childId: '3',
          sessionId: 42,
          drawingRepository: repository,
          syncCoordinator: sync,
          startFresh: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(24, 18));
    await gesture.up();
    await tester.pump();

    await tester.runAsync(() async {
      await tester.binding.handlePopRoute();
      await _waitFor(() => repository.saveDraftCalls == 1);
    });
    await tester.pumpAndSettle();

    expect(repository.strokeBatchCalls, 1);
    expect(repository.saveDraftCalls, 1);
    expect(observer.popCount, 1);
    expect(await routeResult, const DrawingRouteResult.backToActivityEntry());
    expect(find.text('이전 화면'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsNothing);
  });

  testWidgets('빠른 시스템 back과 AppBar back은 저장 뒤 route를 한 번만 pop한다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pendingSave = Completer<DraftSaveResponseDto>();
    final repository = _DraftRepository(pendingSave: pendingSave);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    addTearDown(sync.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _CountingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('이전 화면')),
      ),
    );
    final routeResult = navigatorKey.currentState!.push<DrawingRouteResult>(
      MaterialPageRoute<DrawingRouteResult>(
        builder: (_) => DrawingScreen(
          childId: '3',
          sessionId: 42,
          drawingRepository: repository,
          syncCoordinator: sync,
          startFresh: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(24, 18));
    await gesture.up();
    await tester.pump();

    await tester.tap(find.byTooltip('뒤로 가기'));
    await tester.pump();
    unawaited(tester.binding.handlePopRoute());
    await tester.pump();
    await tester.runAsync(() => _waitFor(() => repository.saveDraftCalls == 1));

    expect(observer.popCount, 0);
    expect(repository.saveDraftCalls, 1);
    pendingSave.complete(
      const DraftSaveResponseDto(
        drawingAssetId: 1,
        assetVersion: 1,
        lastEventSequence: 2,
        savedAt: '2026-07-22T00:00:00Z',
        expiresAt: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(observer.popCount, 1);
    expect(await routeResult, const DrawingRouteResult.backToActivityEntry());
    expect(find.text('이전 화면'), findsOneWidget);
  });

  testWidgets('저장 실패 후 나가기를 선택해도 route를 한 번만 pop한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _DraftRepository(
      saveFailure: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    );
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    addTearDown(sync.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _CountingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('이전 화면')),
      ),
    );
    final routeResult = navigatorKey.currentState!.push<DrawingRouteResult>(
      MaterialPageRoute<DrawingRouteResult>(
        builder: (_) => DrawingScreen(
          childId: '3',
          sessionId: 42,
          drawingRepository: repository,
          syncCoordinator: sync,
          startFresh: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(24, 18));
    await gesture.up();
    await tester.pump();

    unawaited(tester.binding.handlePopRoute());
    await tester.runAsync(() => _waitFor(() => repository.saveDraftCalls == 1));
    await tester.pumpAndSettle();
    expect(find.text('그림을 저장하지 못했어요'), findsOneWidget);
    await tester.tap(find.text('저장하지 않고 나가기'));
    await tester.pumpAndSettle();

    expect(repository.saveDraftCalls, 1);
    expect(observer.popCount, 2);
    expect(observer.pagePopCount, 1);
    expect(await routeResult, const DrawingRouteResult.backToActivityEntry());
    expect(find.text('이전 화면'), findsOneWidget);
  });

  testWidgets('저장 중 화면이 dispose되면 늦은 완료가 route를 pop하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pendingSave = Completer<DraftSaveResponseDto>();
    final repository = _DraftRepository(pendingSave: pendingSave);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    addTearDown(sync.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _CountingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('이전 화면')),
      ),
    );
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => DrawingScreen(
            childId: '3',
            sessionId: 42,
            drawingRepository: repository,
            syncCoordinator: sync,
            startFresh: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(24, 18));
    await gesture.up();
    await tester.pump();

    unawaited(tester.binding.handlePopRoute());
    await tester.runAsync(() => _waitFor(() => repository.saveDraftCalls == 1));
    await tester.pumpWidget(const SizedBox.shrink());
    pendingSave.complete(
      const DraftSaveResponseDto(
        drawingAssetId: 1,
        assetVersion: 1,
        lastEventSequence: 2,
        savedAt: '2026-07-22T00:00:00Z',
        expiresAt: null,
      ),
    );
    await tester.pump();

    expect(observer.popCount, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<DrawingDraftRestoreController> _pumpScreen(
  WidgetTester tester, {
  required _DraftRepository repository,
  required DrawingSyncCoordinator sync,
  bool autoRestoreDraft = false,
  bool startFresh = false,
  Size size = const Size(1200, 800),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final restore = DrawingDraftRestoreController(
    sessionId: 42,
    repository: repository,
    syncCoordinator: sync,
    imageProviderFactory: (_) => MemoryImage(_validPng),
  );
  addTearDown(restore.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: DrawingScreen(
          childId: '3',
          sessionId: 42,
          drawingRepository: repository,
          syncCoordinator: sync,
          draftRestoreController: restore,
          autoRestoreDraft: autoRestoreDraft,
          startFresh: startFresh,
        ),
      ),
    ),
  );
  if (autoRestoreDraft) {
    // 자동 복원 중에는 로딩 표시가 계속 회전하므로 첫 비동기 상태까지만 진행한다.
    for (var attempt = 0; attempt < 10; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 20));
      if (restore.status == DrawingDraftRestoreStatus.loadingImage) break;
    }
  } else {
    await tester.pumpAndSettle();
  }
  return restore;
}

DrawingCanvas _canvas(WidgetTester tester) =>
    tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));

final _validPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);

DrawingStroke _stroke() => const DrawingStroke(
  color: AppColors.drawingInk,
  thickness: 8,
  points: [
    DrawingPoint(position: Offset(10, 10), elapsedMilliseconds: 10),
    DrawingPoint(position: Offset(20, 20), elapsedMilliseconds: 20),
  ],
);

enum _Scenario { found, absent, empty, failure }

final class _DraftRepository implements DrawingRepository {
  _DraftRepository({
    this.scenario = _Scenario.found,
    this.nullSequences = false,
    this.pendingDraft,
    this.pendingPreview,
    this.failure,
    this.pendingSave,
    this.saveFailure,
  });

  _Scenario scenario;
  final bool nullSequences;
  final Completer<DraftRecoveryDto?>? pendingDraft;
  final Completer<Uint8List>? pendingPreview;
  final Object? failure;
  final Completer<DraftSaveResponseDto>? pendingSave;
  final Object? saveFailure;
  int getDraftCalls = 0;
  int downloadDraftPreviewCalls = 0;
  int deleteDraftCalls = 0;
  String? downloadedPreviewUrl;
  StrokeBatchRequestDto? lastBatch;
  BinaryUploadDto? savedImage;
  int? savedLastEventSequence;
  int strokeBatchCalls = 0;
  int saveDraftCalls = 0;

  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async {
    getDraftCalls += 1;
    if (pendingDraft case final pending?) return pending.future;
    if (scenario == _Scenario.failure) {
      throw failure ??
          const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
    if (scenario == _Scenario.absent) {
      throw ApiResponseFailure(
        statusCode: 404,
        error: ApiError(
          timestamp: '2026-07-22T00:00:00Z',
          path: '/api/v1/drawing-sessions/$sessionId/draft',
          code: 'DRAWING_404_004',
          message: 'not found',
        ),
      );
    }
    if (scenario == _Scenario.empty) return null;
    if (!nullSequences) return _draftRecovery;
    return const DraftRecoveryDto(
      previewUrl: 'https://example.test/draft.png',
      canvasState: DraftCanvasStateDto(
        lastEventSequence: null,
        toolState: null,
        viewport: null,
        clientSavedAt: '2026-07-21T09:41:10Z',
      ),
      assetVersion: 3,
    );
  }

  @override
  Future<Uint8List> downloadDraftPreview(String previewUrl) async {
    downloadDraftPreviewCalls += 1;
    downloadedPreviewUrl = previewUrl;
    if (pendingPreview case final pending?) return pending.future;
    if (scenario == _Scenario.failure) {
      throw failure ??
          const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
    return _validPng;
  }

  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async => null;

  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async {
    strokeBatchCalls += 1;
    lastBatch = request;
    return StrokeBatchResponseDto(
      batchId: 1,
      batchSequence: request.batchSequence,
      acceptedEventCount: request.events.length,
      lastEventSequence: request.lastEventSequence,
      receivedAt: '2026-07-22T00:00:00Z',
    );
  }

  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState, {
    required String idempotencyKey,
  }) async {
    saveDraftCalls += 1;
    savedImage = preview;
    savedLastEventSequence = canvasState.lastEventSequence;
    if (pendingSave case final pending?) return pending.future;
    if (saveFailure case final failure?) throw failure;
    return DraftSaveResponseDto(
      drawingAssetId: 1,
      assetVersion: 3,
      lastEventSequence: canvasState.lastEventSequence,
      savedAt: '2026-07-22T00:00:00Z',
      expiresAt: null,
    );
  }

  @override
  Future<void> deleteDraft(int sessionId) async => deleteDraftCalls += 1;

  @override
  Future<DrawingStageCompleteResponseDto> completeDrawingStage(
    int sessionId, {
    required BinaryUploadDto finalImage,
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DrawingCompletionResponseDto> completeActivity(
    int sessionId, {
    required CompleteActivityRequestDto request,
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DrawingSessionDto> getSession(int sessionId) =>
      throw UnimplementedError();
  @override
  Future<DrawingTypePage> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) => throw UnimplementedError();
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
  }) => throw UnimplementedError();
}

const _asset = DrawingAssetDto(
  assetId: 120,
  assetType: 'DRAFT',
  assetVersion: 3,
  fileUrl: 'https://example.test/draft.png',
  mimeType: 'image/png',
  widthPx: 100,
  heightPx: 100,
);

const _draftRecovery = DraftRecoveryDto(
  previewUrl: 'https://example.test/draft.png',
  canvasState: DraftCanvasStateDto(
    lastEventSequence: 1105,
    toolState: null,
    viewport: null,
    clientSavedAt: '2026-07-21T09:41:10Z',
  ),
  assetVersion: 3,
);

final class _CountingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;
  int pagePopCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount += 1;
    if (route is PageRoute<dynamic>) pagePopCount += 1;
    super.didPop(route, previousRoute);
  }
}
