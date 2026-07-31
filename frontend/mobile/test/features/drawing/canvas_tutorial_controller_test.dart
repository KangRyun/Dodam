import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/drawing/application/canvas_tutorial_controller.dart';

void main() {
  group('CanvasTutorialController', () {
    test('최초 진입은 PEN 단계로 시작하고 IN_PROGRESS를 저장한다', () async {
      final backend = _TutorialBackend(status: 'NOT_STARTED');
      final controller = _controller(backend);

      await controller.load();

      expect(controller.isVisible, isTrue);
      expect(controller.step, CanvasTutorialStep.pen);
      expect(backend.requests.map((request) => request.toJson()), [
        {'tutorialStatus': 'IN_PROGRESS', 'lastStep': 'PEN'},
      ]);
    });

    test('진행 중인 튜토리얼은 서버 lastStep부터 복원한다', () async {
      final backend = _TutorialBackend(
        status: 'IN_PROGRESS',
        lastStep: 'THICKNESS',
      );
      final controller = _controller(backend);

      await controller.load();

      expect(controller.isVisible, isTrue);
      expect(controller.step, CanvasTutorialStep.thickness);
      expect(backend.requests, isEmpty);
    });

    test('완료 상태는 자동 노출하지 않고 수동 다시 보기는 서버를 변경하지 않는다', () async {
      final backend = _TutorialBackend(status: 'COMPLETED');
      final controller = _controller(backend);

      await controller.load();
      expect(controller.isVisible, isFalse);

      controller.replay();
      expect(controller.isVisible, isTrue);
      expect(controller.step, CanvasTutorialStep.pen);

      await controller.next();
      await controller.skip();
      expect(backend.requests, isEmpty);
      expect(controller.isVisible, isFalse);
    });

    test('다음 단계와 완료를 서버에 저장한다', () async {
      final backend = _TutorialBackend(
        status: 'IN_PROGRESS',
        lastStep: 'UNDO_REDO',
      );
      final controller = _controller(backend);

      await controller.load();
      await controller.next();
      expect(controller.step, CanvasTutorialStep.complete);

      await controller.next();
      expect(controller.isVisible, isFalse);
      expect(backend.requests.map((request) => request.toJson()), [
        {'tutorialStatus': 'IN_PROGRESS', 'lastStep': 'COMPLETE'},
        {'tutorialStatus': 'COMPLETED', 'lastStep': 'COMPLETE'},
      ]);
    });

    test('건너뛰기는 현재 단계와 SKIPPED를 저장한다', () async {
      final backend = _TutorialBackend(
        status: 'IN_PROGRESS',
        lastStep: 'COLOR',
      );
      final controller = _controller(backend);

      await controller.load();
      await controller.skip();

      expect(controller.isVisible, isFalse);
      expect(backend.requests.single.toJson(), {
        'tutorialStatus': 'SKIPPED',
        'lastStep': 'COLOR',
      });
    });

    test('조회 실패는 재시도 가능한 오류 상태로 두고 Canvas를 잠그지 않는다', () async {
      final backend = _TutorialBackend(
        status: 'NOT_STARTED',
        loadError: StateError('offline'),
      );
      final controller = _controller(backend);

      await controller.load();

      expect(controller.hasError, isTrue);
      expect(controller.isVisible, isTrue);
      expect(controller.blocksCanvas, isFalse);

      backend.loadError = null;
      await controller.retry();
      expect(controller.hasError, isFalse);
      expect(controller.step, CanvasTutorialStep.pen);
    });

    test('단계 저장 실패는 현재 단계를 유지하고 재시도할 수 있다', () async {
      final backend = _TutorialBackend(
        status: 'IN_PROGRESS',
        lastStep: 'PEN',
        saveError: StateError('timeout'),
      );
      final controller = _controller(backend);
      await controller.load();

      await controller.next();
      expect(controller.step, CanvasTutorialStep.pen);
      expect(controller.hasError, isTrue);

      backend.saveError = null;
      await controller.retry();
      expect(controller.step, CanvasTutorialStep.eraser);
      expect(controller.hasError, isFalse);
    });

    test('화면 종료 뒤 늦게 도착한 조회 응답은 예외 없이 무시한다', () async {
      final response = Completer<TutorialProgressDto>();
      final controller = CanvasTutorialController(
        childId: 7,
        loadProgress: (_) => response.future,
        saveProgress: (_, _) async =>
            _TutorialBackend(status: 'IN_PROGRESS').load(7),
      );

      final loading = controller.load();
      controller.dispose();
      response.complete(
        TutorialProgressDto(
          childId: 7,
          tutorialStatus: 'COMPLETED',
          lastStep: null,
          completedAt: null,
          updatedAt: '2026-07-31T00:00:00Z',
        ),
      );

      await expectLater(loading, completes);
    });
  });
}

CanvasTutorialController _controller(_TutorialBackend backend) =>
    CanvasTutorialController(
      childId: 7,
      loadProgress: backend.load,
      saveProgress: backend.save,
    );

final class _TutorialBackend {
  _TutorialBackend({
    required this.status,
    this.lastStep,
    this.loadError,
    this.saveError,
  });

  String status;
  String? lastStep;
  Object? loadError;
  Object? saveError;
  final List<UpdateTutorialRequestDto> requests = [];

  Future<TutorialProgressDto> load(int childId) async {
    if (loadError case final error?) throw error;
    return _progress(childId);
  }

  Future<TutorialProgressDto> save(
    int childId,
    UpdateTutorialRequestDto request,
  ) async {
    if (saveError case final error?) throw error;
    requests.add(request);
    status = request.tutorialStatus;
    lastStep = request.lastStep;
    return _progress(childId);
  }

  TutorialProgressDto _progress(int childId) => TutorialProgressDto(
    childId: childId,
    tutorialStatus: status,
    lastStep: lastStep,
    completedAt: null,
    updatedAt: '2026-07-31T00:00:00Z',
  );
}
