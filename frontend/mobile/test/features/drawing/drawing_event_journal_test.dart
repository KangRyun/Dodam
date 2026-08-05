import 'dart:ui';

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/drawing/application/drawing_event_journal.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('snapshot cutoff sequence', () {
    test('starts at zero before the session allocates an event', () {
      final journal = DrawingEventJournal();

      expect(journal.snapshotCutoffSequence, 0);
    });

    test('keeps the restored cutoff while the journal has no events', () {
      final journal = DrawingEventJournal();

      expect(journal.resumeEventSequence(1106), isTrue);

      expect(journal.events, isEmpty);
      expect(journal.snapshotCutoffSequence, 1105);
    });

    test('tracks the allocator cutoff after recording new events', () {
      final journal = DrawingEventJournal(
        sequenceAllocator: SessionSequenceAllocator(startValue: 41),
      );

      journal.recordStroke(_stroke(10), const Size(100, 100));

      expect(journal.snapshotCutoffSequence, 42);
    });
  });

  test('stroke를 START MOVE END로 변환하고 좌표와 속성을 보존한다', () {
    final allocator = SessionSequenceAllocator(startValue: 41);
    final events = DrawingStrokeEventConverter.convert(
      stroke: const DrawingStroke(
        color: AppColors.drawingRed,
        thickness: 8,
        points: [
          DrawingPoint(
            position: Offset(-10, 20),
            elapsedMilliseconds: 100,
            pressure: 0.4,
          ),
          DrawingPoint(position: Offset(50, 75), elapsedMilliseconds: 120),
          DrawingPoint(
            position: Offset(120, 110),
            elapsedMilliseconds: 150,
            pressure: 0.8,
          ),
        ],
      ),
      canvasSize: const Size(100, 100),
      sequenceAllocator: allocator,
    );

    expect(events.map((event) => event.type), [
      'STROKE_START',
      'STROKE_MOVE',
      'STROKE_END',
    ]);
    expect(events.map((event) => event.seq), [41, 42, 43]);
    expect(events.map((event) => event.t), [100, 120, 150]);
    expect(events.first.x, 0);
    expect(events.first.y, 0.2);
    expect(events.last.x, 1);
    expect(events.last.y, 1);
    expect(events.first.tool, 'PEN');
    expect(events.first.color, '#E35D6A');
    expect(events.first.thickness, 8);
    expect(events[1].toJson(), isNot(contains('pressure')));
    expect(events.last.pressure, 0.8);
  });

  test('seq는 여러 stroke와 batch 경계와 무관하게 journal 전체에서 증가한다', () {
    final journal = DrawingEventJournal(
      sequenceAllocator: SessionSequenceAllocator(startValue: 7),
    );
    final first = journal.recordStroke(_stroke(10), const Size(100, 100));
    final second = journal.recordStroke(_stroke(30), const Size(100, 100));

    expect(first.map((event) => event.seq), [7, 8]);
    expect(second.map((event) => event.seq), [9, 10]);
    expect(journal.lastEventSequence, 10);
    expect(journal.events, hasLength(4));
  });

  test('지우개 stroke는 ERASER 도구와 굵기를 보존하고 색상은 전송하지 않는다', () {
    final events = DrawingStrokeEventConverter.convert(
      stroke: const DrawingStroke(
        tool: DrawingTool.eraser,
        color: AppColors.drawingRed,
        thickness: 14,
        points: [
          DrawingPoint(
            position: Offset(10, 20),
            elapsedMilliseconds: 100,
            pressure: 0.25,
          ),
          DrawingPoint(
            position: Offset(30, 40),
            elapsedMilliseconds: 120,
            pressure: 0.75,
          ),
        ],
      ),
      canvasSize: const Size(100, 100),
      sequenceAllocator: SessionSequenceAllocator(),
    );

    expect(events.first.tool, 'ERASER');
    expect(events.first.color, isNull);
    expect(events.first.thickness, 14);
    expect(events.map((event) => event.pressure), [0.25, 0.75]);
    expect(events.first.toJson(), isNot(contains('color')));
    expect(events.map((event) => event.type), ['STROKE_START', 'STROKE_END']);
  });

  test('단일 point stroke는 동일 좌표의 START END를 생성하고 seq 2개를 소비한다', () {
    final allocator = SessionSequenceAllocator(startValue: 5);
    final events = DrawingStrokeEventConverter.convert(
      stroke: const DrawingStroke(
        color: AppColors.drawingInk,
        thickness: 4,
        points: [DrawingPoint(position: Offset.zero, elapsedMilliseconds: 1)],
      ),
      canvasSize: const Size(100, 100),
      sequenceAllocator: allocator,
    );

    expect(events.map((event) => event.type), ['STROKE_START', 'STROKE_END']);
    expect(events.map((event) => event.seq), [5, 6]);
    expect(events[0].x, events[1].x);
    expect(events[0].y, events[1].y);
    expect(events[1].tool, isNull);
    expect(events[1].color, isNull);
    expect(events[1].thickness, isNull);
    expect(allocator.nextValue, 7);
  });

  test('UNDO는 기존 stroke event를 유지하고 seq t type만 append한다', () {
    final journal = DrawingEventJournal();
    journal.recordStroke(_stroke(10), const Size(100, 100));
    final snapshot = journal.events;
    final undo = journal.recordUndo(elapsedMilliseconds: 30)!;

    expect(() => snapshot.clear(), throwsUnsupportedError);
    expect(journal.events, hasLength(3));
    expect(journal.events.take(2).map((event) => event.type), [
      'STROKE_START',
      'STROKE_END',
    ]);
    expect(undo.seq, 3);
    expect(undo.t, 30);
    expect(undo.type, 'UNDO');
    expect(undo.toJson().keys, {'seq', 't', 'type'});
  });

  test('연속 UNDO는 LIFO 가능 횟수만 append하고 빈 상태에서는 생성하지 않는다', () {
    final journal = DrawingEventJournal();
    journal
      ..recordStroke(_stroke(10), const Size(100, 100))
      ..recordStroke(_stroke(30), const Size(100, 100));

    expect(journal.recordUndo(elapsedMilliseconds: 50)?.seq, 5);
    expect(journal.recordUndo(elapsedMilliseconds: 60)?.seq, 6);
    expect(journal.recordUndo(elapsedMilliseconds: 70), isNull);
    expect(journal.events.where((event) => event.type == 'UNDO').length, 2);
    expect(journal.lastEventSequence, 6);
  });

  test('REDO는 Undo한 획만 복원하고 새 stroke가 생기면 다시 실행 이력을 비운다', () {
    final journal = DrawingEventJournal();
    journal
      ..recordStroke(_stroke(10), const Size(100, 100))
      ..recordStroke(_stroke(30), const Size(100, 100));

    expect(journal.recordUndo(elapsedMilliseconds: 50), isNotNull);
    final redo = journal.recordRedo(elapsedMilliseconds: 60)!;
    expect(redo.type, 'REDO');
    expect(redo.seq, 6);
    expect(journal.undoableStrokeCount, 2);
    expect(journal.redoableStrokeCount, 0);

    expect(journal.recordUndo(elapsedMilliseconds: 70), isNotNull);
    journal.recordStroke(_stroke(80), const Size(100, 100));
    expect(journal.redoableStrokeCount, 0);
    expect(journal.recordRedo(elapsedMilliseconds: 90), isNull);
  });

  group('도구 설정 변경', () {
    test('끄는 동안의 중간 값은 마지막 하나로 합치고 고른 시각을 유지한다', () {
      final journal = DrawingEventJournal()
        ..recordStroke(_stroke(10), const Size(100, 100));

      for (var value = 1; value <= 20; value++) {
        journal.recordColorChange(
          Color(0xFF000000 + value),
          elapsedMilliseconds: 100 + value,
        );
      }
      journal.recordStroke(_stroke(200), const Size(100, 100));

      final colorChanges = journal.events
          .where((event) => event.type == 'COLOR_CHANGE')
          .toList();
      expect(colorChanges, hasLength(1));
      expect(colorChanges.single.color, '#000014');
      // 굳힌 때가 아니라 아이가 그 값을 고른 때다.
      expect(colorChanges.single.t, 120);
    });

    test('고른 순서대로 굳고 다음 획보다 앞선다', () {
      final journal = DrawingEventJournal()
        ..recordStroke(_stroke(10), const Size(100, 100))
        ..recordThicknessChange(14, elapsedMilliseconds: 300)
        ..recordToolChange('PENCIL', elapsedMilliseconds: 100)
        ..recordColorChange(
          const Color(0xFF112233),
          elapsedMilliseconds: 200,
        );

      expect(
        journal.events.map((event) => event.type),
        ['STROKE_START', 'STROKE_END'],
        reason: '캔버스 행동이나 전송 전에는 굳지 않는다',
      );

      journal.recordStroke(_stroke(400), const Size(100, 100));

      expect(journal.events.map((event) => event.type), [
        'STROKE_START',
        'STROKE_END',
        'TOOL_CHANGE',
        'COLOR_CHANGE',
        'THICKNESS_CHANGE',
        'STROKE_START',
        'STROKE_END',
      ]);
      expect(journal.events.map((event) => event.seq), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('이미 기록한 값과 같으면 event를 만들지 않는다', () {
      final journal = DrawingEventJournal()
        ..recordStroke(_stroke(10), const Size(100, 100))
        ..recordToolChange('PENCIL', elapsedMilliseconds: 100);
      journal.recordStroke(_stroke(200), const Size(100, 100));

      journal
        ..recordToolChange('PENCIL', elapsedMilliseconds: 300)
        ..recordStroke(_stroke(400), const Size(100, 100));

      expect(
        journal.events.where((event) => event.type == 'TOOL_CHANGE'),
        hasLength(1),
      );
    });

    test('순번 복원 구간에는 굳지 않아 Draft 이어그리기를 깨지 않는다', () {
      final journal = DrawingEventJournal()
        ..recordColorChange(const Color(0xFF445566), elapsedMilliseconds: 50)
        ..commitPendingSettings();

      expect(journal.events, isEmpty);
      expect(journal.resumeEventSequence(1106), isTrue);

      journal.commitPendingSettings();
      expect(journal.events.single.type, 'COLOR_CHANGE');
      expect(journal.events.single.seq, 1106);
    });
  });

  group('멈춤', () {
    test('임계값 이상 비면 PAUSE RESUME 짝을 붙여 남긴다', () {
      final journal = DrawingEventJournal()
        ..recordStroke(_stroke(0), const Size(100, 100))
        ..recordStroke(_stroke(3010), const Size(100, 100));

      final pauses = journal.events
          .where(
            (event) => event.type == 'PAUSE' || event.type == 'RESUME',
          )
          .toList();
      expect(pauses.map((event) => event.type), ['PAUSE', 'RESUME']);
      // 앞 획의 마지막 점(5ms)부터 다음 획의 첫 점(3010ms)까지다.
      expect(pauses.map((event) => event.t), [5, 3010]);
      expect(pauses.first.seq + 1, pauses.last.seq);
    });

    test('임계값 미만은 멈춤으로 세지 않는다', () {
      final journal = DrawingEventJournal()
        ..recordStroke(_stroke(0), const Size(100, 100))
        ..recordStroke(_stroke(2500), const Size(100, 100));

      expect(
        journal.events.where((event) => event.type == 'PAUSE'),
        isEmpty,
      );
    });

    test('첫 획 전의 시간은 멈춤이 아니다', () {
      final journal = DrawingEventJournal()
        ..recordStroke(_stroke(60000), const Size(100, 100));

      expect(
        journal.events.map((event) => event.type),
        ['STROKE_START', 'STROKE_END'],
      );
    });

    test('백그라운드에 다녀온 시간은 기준 시각을 옮겨 제외한다', () {
      final journal = DrawingEventJournal()
        ..recordStroke(_stroke(0), const Size(100, 100))
        ..resetIdleClock(elapsedMilliseconds: 600000)
        ..recordStroke(_stroke(600100), const Size(100, 100));

      expect(
        journal.events.where((event) => event.type == 'PAUSE'),
        isEmpty,
      );
    });

    test('마지막 획 뒤에 남은 멈춤은 완료 직전에 닫는다', () {
      final journal = DrawingEventJournal()
        ..recordStroke(_stroke(0), const Size(100, 100))
        ..closeTrailingPause(elapsedMilliseconds: 9000);

      expect(journal.events.map((event) => event.type), [
        'STROKE_START',
        'STROKE_END',
        'PAUSE',
        'RESUME',
      ]);
      expect(journal.events.last.t - journal.events[2].t, 8995);
    });
  });

  group('채우기와 전체 지우기', () {
    test('FILL은 정규화 좌표와 색을 싣고 되돌릴 수 있는 변경으로 센다', () {
      final journal = DrawingEventJournal();
      final fill = journal.recordFill(
        color: const Color(0xFF00FF00),
        documentPoint: const Offset(25, 75),
        canvasSize: const Size(100, 100),
        elapsedMilliseconds: 40,
      );

      expect(fill.type, 'FILL');
      expect(fill.x, 0.25);
      expect(fill.y, 0.75);
      expect(fill.color, '#00FF00');
      expect(journal.undoableStrokeCount, 1);
      expect(journal.recordUndo(elapsedMilliseconds: 50)?.type, 'UNDO');
    });

    test('CANVAS_CLEAR는 되돌리기·다시 실행 가능 수를 함께 비운다', () {
      final journal = DrawingEventJournal()
        ..recordStroke(_stroke(10), const Size(100, 100))
        ..recordStroke(_stroke(30), const Size(100, 100));
      journal.recordUndo(elapsedMilliseconds: 50);
      expect(journal.redoableStrokeCount, 1);

      final clear = journal.recordCanvasClear(elapsedMilliseconds: 60);

      expect(clear.type, 'CANVAS_CLEAR');
      expect(journal.undoableStrokeCount, 0);
      expect(journal.redoableStrokeCount, 0);
      expect(journal.recordUndo(elapsedMilliseconds: 70), isNull);
      expect(journal.recordRedo(elapsedMilliseconds: 80), isNull);
    });
  });

  test('drainPendingEvents는 아직 넘기지 않은 event만 한 번씩 돌려준다', () {
    final journal = DrawingEventJournal()
      ..recordStroke(_stroke(10), const Size(100, 100));

    expect(journal.drainPendingEvents().map((event) => event.seq), [1, 2]);
    expect(journal.drainPendingEvents(), isEmpty);

    journal.recordUndo(elapsedMilliseconds: 30);
    expect(journal.drainPendingEvents().map((event) => event.seq), [3]);
  });
}

DrawingStroke _stroke(int t) => DrawingStroke(
  color: AppColors.drawingInk,
  thickness: 4,
  points: [
    DrawingPoint(position: const Offset(10, 10), elapsedMilliseconds: t),
    DrawingPoint(position: const Offset(20, 20), elapsedMilliseconds: t + 5),
  ],
);
