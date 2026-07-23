import 'dart:ui';

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/drawing/application/drawing_event_journal.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}

DrawingStroke _stroke(int t) => DrawingStroke(
  color: AppColors.drawingInk,
  thickness: 4,
  points: [
    DrawingPoint(position: const Offset(10, 10), elapsedMilliseconds: t),
    DrawingPoint(position: const Offset(20, 20), elapsedMilliseconds: t + 5),
  ],
);
