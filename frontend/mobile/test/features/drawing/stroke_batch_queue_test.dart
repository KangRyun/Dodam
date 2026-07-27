import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('START MOVE END를 END sequence의 단일 STROKE로 집약한다', () async {
    final queue = _queue();
    queue.addEvents([
      _pointEvent(
        seq: 11,
        t: 100,
        type: 'STROKE_START',
        x: 0.1,
        y: 0.2,
        pressure: 0.4,
        includeStyle: true,
      ),
      _pointEvent(seq: 12, t: 120, type: 'STROKE_MOVE', x: 0.3, y: 0.4),
      _pointEvent(
        seq: 13,
        t: 150,
        type: 'STROKE_END',
        x: 0.5,
        y: 0.6,
        pressure: 0.8,
      ),
    ]);

    await queue.flush();

    final request = queue.pendingBatches.single.request;
    final stroke = request.events.single;
    expect(request.batchSequence, 1);
    expect(request.firstEventSequence, 13);
    expect(request.lastEventSequence, 13);
    expect(request.clientCreatedAt, '2026-07-22T01:02:03.000Z');
    expect(stroke.sequence, 13);
    expect(stroke.eventType, 'STROKE');
    expect(stroke.tool, 'PEN');
    expect(stroke.color, '#E35D6A');
    expect(stroke.width, 8);
    expect(stroke.points.map((point) => point.t), [0, 20, 50]);
    expect(stroke.points.map((point) => point.x), [0.1, 0.3, 0.5]);
    expect(stroke.points.map((point) => point.y), [0.2, 0.4, 0.6]);
    expect(stroke.points.map((point) => point.pressure), [0.4, null, 0.8]);
    expect(stroke.points[1].toJson(), isNot(contains('pressure')));
    expect(request.metrics.toJson(), {
      'undoCountDelta': 0,
      'redoCountDelta': 0,
      'eraseCountDelta': 0,
      'pauseDurationMsDelta': 0,
    });
  });

  test('여러 Stroke와 Undo를 순서대로 보존하고 sequence 누락을 허용한다', () async {
    final queue = _queue();
    queue.addEvents([
      ..._stroke(startSeq: 21, endSeq: 23, startTime: 100),
      ..._stroke(startSeq: 30, endSeq: 31, startTime: 200),
      const StrokeEventDto(seq: 35, t: 260, type: 'UNDO'),
    ]);

    await queue.flush();

    final request = queue.pendingBatches.single.request;
    expect(request.events.map((event) => event.eventType), [
      'STROKE',
      'STROKE',
      'UNDO',
    ]);
    expect(request.events.map((event) => event.sequence), [23, 31, 35]);
    expect(request.firstEventSequence, 23);
    expect(request.lastEventSequence, 35);
    expect(request.events.last.points, isEmpty);
    expect(request.events.last.tool, isNull);
    expect(request.events.last.color, isNull);
    expect(request.events.last.width, isNull);
    expect(request.metrics.undoCountDelta, 1);
  });

  test('PEN과 ERASER를 순서대로 보존하고 지우개 횟수를 집계한다', () async {
    final queue = _queue();
    queue.addEvents([
      ..._stroke(startSeq: 1, endSeq: 3, startTime: 10),
      ..._stroke(
        startSeq: 5,
        endSeq: 7,
        startTime: 40,
        tool: 'ERASER',
        color: null,
        width: 14,
      ),
      const StrokeEventDto(seq: 9, t: 80, type: 'UNDO'),
    ]);

    await queue.flush();

    final request = queue.pendingBatches.single.request;
    expect(request.events.map((event) => event.eventType), [
      'STROKE',
      'STROKE',
      'UNDO',
    ]);
    expect(request.events.map((event) => event.sequence), [3, 7, 9]);
    expect(request.firstEventSequence, 3);
    expect(request.lastEventSequence, 9);
    expect(request.events[0].tool, 'PEN');
    expect(request.events[1].tool, 'ERASER');
    expect(request.events[1].color, isNull);
    expect(request.events[1].width, 14);
    expect(request.metrics.undoCountDelta, 1);
    expect(request.metrics.eraseCountDelta, 1);
  });

  test('ERASER-only batch는 eraseCountDelta를 stroke 수만큼 전송한다', () async {
    final queue = _queue();
    queue.addEvents([
      ..._stroke(
        startSeq: 11,
        endSeq: 12,
        startTime: 100,
        tool: 'ERASER',
        color: null,
        startPressure: 0.2,
        endPressure: 0.8,
      ),
      ..._stroke(
        startSeq: 20,
        endSeq: 22,
        startTime: 130,
        tool: 'ERASER',
        color: null,
      ),
    ]);

    await queue.flush();

    final request = queue.pendingBatches.single.request;
    expect(request.events.every((event) => event.tool == 'ERASER'), isTrue);
    expect(request.events.first.toJson(), {
      'sequence': 12,
      'eventType': 'STROKE',
      'tool': 'ERASER',
      'width': 8.0,
      'points': [
        {'x': 0.1, 'y': 0.2, 't': 0, 'pressure': 0.2},
        {'x': 0.3, 'y': 0.4, 't': 20, 'pressure': 0.8},
      ],
    });
    expect(request.metrics.eraseCountDelta, 2);
    expect(request.metrics.undoCountDelta, 0);
    expect(request.firstEventSequence, 12);
    expect(request.lastEventSequence, 22);
  });

  test('Undo-only batch도 event와 metrics를 함께 전송한다', () async {
    final queue = _queue();
    queue.addEvents([
      const StrokeEventDto(seq: 41, t: 300, type: 'UNDO'),
      const StrokeEventDto(seq: 45, t: 320, type: 'UNDO'),
    ]);

    await queue.flush();

    final request = queue.pendingBatches.single.request;
    expect(request.events.map((event) => event.sequence), [41, 45]);
    expect(request.events.every((event) => event.points.isEmpty), isTrue);
    expect(request.firstEventSequence, 41);
    expect(request.lastEventSequence, 45);
    expect(request.metrics.undoCountDelta, 2);
  });

  test('불완전 Stroke는 버퍼에 보존하고 END 확보 후 전송한다', () async {
    final queue = _queue();
    final stroke = _stroke(startSeq: 51, endSeq: 53, startTime: 400);
    queue.addEvents(stroke.take(2));

    await queue.flush();

    expect(queue.pendingBatches, isEmpty);
    expect(queue.bufferedEvents.map((event) => event.seq), [51, 52]);

    queue.addEvents(stroke.skip(2));
    await queue.flush();

    expect(queue.bufferedEvents, isEmpty);
    expect(queue.pendingBatches.single.request.events.single.sequence, 53);
    expect(queue.pendingBatches.single.request.batchSequence, 1);
  });

  test('성공 ack는 완결 Stroke와 Undo만 제거하고 trailing Stroke를 보존한다', () async {
    final sentRequests = <StrokeBatchRequestDto>[];
    final queue = StrokeBatchQueue(
      sessionId: 42,
      sender: (sessionId, request) async {
        sentRequests.add(request);
        return _response(request);
      },
      policy: const DrawingSyncPolicy(eventThreshold: 100),
      now: () => DateTime.utc(2026, 7, 22, 1, 2, 3),
    );
    final trailingStroke = _stroke(startSeq: 8, endSeq: 10, startTime: 80);
    queue.addEvents([
      ..._stroke(startSeq: 1, endSeq: 3, startTime: 10),
      const StrokeEventDto(seq: 4, t: 40, type: 'UNDO'),
      ..._stroke(startSeq: 5, endSeq: 7, startTime: 50),
      ...trailingStroke.take(2),
    ]);

    await queue.flush();

    expect(sentRequests, hasLength(1));
    final request = sentRequests.single;
    expect(request.events.map((event) => event.eventType), [
      'STROKE',
      'UNDO',
      'STROKE',
    ]);
    expect(request.events.map((event) => event.sequence), [3, 4, 7]);
    expect(request.metrics.undoCountDelta, 1);
    expect(queue.pendingBatches, isEmpty);
    expect(queue.completedBatches, hasLength(1));
    expect(
      queue.completedBatches.single.status,
      StrokeBatchQueueStatus.success,
    );
    expect(identical(queue.completedBatches.single.request, request), isTrue);
    expect(queue.bufferedEvents.map((event) => event.seq), [8, 9]);

    await queue.flush();

    expect(sentRequests, hasLength(1));
    expect(queue.pendingBatches, isEmpty);
    expect(queue.completedBatches, hasLength(1));
    expect(queue.bufferedEvents.map((event) => event.seq), [8, 9]);
  });

  test('불완전 Stroke 뒤의 다른 event는 실패시키고 버퍼를 보존한다', () async {
    final queue = _queue();
    queue.addEvents([
      _pointEvent(
        seq: 61,
        t: 500,
        type: 'STROKE_START',
        x: 0.1,
        y: 0.2,
        includeStyle: true,
      ),
      const StrokeEventDto(seq: 62, t: 510, type: 'UNDO'),
    ]);

    await expectLater(queue.flush(), throwsStateError);

    expect(queue.pendingBatches, isEmpty);
    expect(queue.bufferedEvents.map((event) => event.seq), [61, 62]);
  });

  test('잘못된 raw sequence와 고립된 MOVE를 조용히 허용하지 않는다', () async {
    final duplicateSequenceQueue = _queue();
    duplicateSequenceQueue.addEvents([
      ..._stroke(startSeq: 71, endSeq: 73, startTime: 600),
      const StrokeEventDto(seq: 73, t: 630, type: 'UNDO'),
    ]);
    await expectLater(duplicateSequenceQueue.flush(), throwsStateError);

    final orphanMoveQueue = _queue();
    orphanMoveQueue.addEvents([
      _pointEvent(seq: 80, t: 700, type: 'STROKE_MOVE', x: 0.2, y: 0.3),
    ]);
    await expectLater(orphanMoveQueue.flush(), throwsStateError);
  });

  test('retry는 clientCreatedAt을 포함한 동일 객체와 payload를 재사용한다', () async {
    final requests = <StrokeBatchRequestDto>[];
    var nowCalls = 0;
    var fail = true;
    final queue = StrokeBatchQueue(
      sessionId: 42,
      sender: (sessionId, request) async {
        requests.add(request);
        if (fail) {
          throw const ApiTransportFailure(
            type: ApiTransportFailureType.connection,
          );
        }
        return _response(request);
      },
      policy: const DrawingSyncPolicy(maxRetryAttempts: 3),
      now: () {
        nowCalls += 1;
        return DateTime.utc(2026, 7, 22, 1, 2, 3);
      },
    );
    queue.addEvents(
      _stroke(
        startSeq: 1,
        endSeq: 3,
        startTime: 10,
        tool: 'ERASER',
        color: null,
      ),
    );
    await queue.flush();
    final failedRequest = queue.pendingBatches.single.request;
    final failedPayload = failedRequest.toJson();

    fail = false;
    await queue.retryHead();

    expect(nowCalls, 1);
    expect(requests, hasLength(2));
    expect(identical(requests[0], requests[1]), isTrue);
    expect(identical(requests[0], failedRequest), isTrue);
    expect(requests[1].toJson(), failedPayload);
    expect(requests[1].events.single.tool, 'ERASER');
    expect(requests[1].metrics.eraseCountDelta, 1);
    expect(queue.pendingBatches, isEmpty);
    expect(
      queue.completedBatches.single.status,
      StrokeBatchQueueStatus.success,
    );
  });

  test('앞 batch 실패 중에는 다음 batch를 전송하지 않고 입력을 계속 받는다', () async {
    var calls = 0;
    final queue = StrokeBatchQueue(
      sessionId: 42,
      sender: (sessionId, request) async {
        calls += 1;
        throw const ApiTransportFailure(
          type: ApiTransportFailureType.connection,
        );
      },
      policy: const DrawingSyncPolicy(eventThreshold: 100),
    );
    queue.addEvents(_stroke(startSeq: 1, endSeq: 2, startTime: 10));
    await queue.flush();
    queue.addEvents(_stroke(startSeq: 3, endSeq: 4, startTime: 30));
    await queue.flush();
    queue.addEvents(_stroke(startSeq: 5, endSeq: 6, startTime: 50));

    expect(calls, 1);
    expect(queue.pendingBatches, hasLength(2));
    expect(queue.bufferedEvents, hasLength(2));
    expect(
      queue.pendingBatches.first.status,
      StrokeBatchQueueStatus.failedRetryable,
    );
  });

  test('HTTP 성공 및 retry 분류는 계약 상태 코드를 따른다', () {
    expect(StrokeRetryPolicy.isSuccessStatus(200), isTrue);
    expect(StrokeRetryPolicy.isSuccessStatus(201), isTrue);
    for (final code in [400, 403, 404, 409]) {
      expect(
        StrokeRetryPolicy.isRetryable(
          ApiResponseFailure(statusCode: code, error: null),
        ),
        isFalse,
      );
    }
    expect(
      StrokeRetryPolicy.isRetryable(
        const ApiResponseFailure(statusCode: 503, error: null),
      ),
      isTrue,
    );
    expect(
      StrokeRetryPolicy.isRetryable(
        const ApiTransportFailure(type: ApiTransportFailureType.connection),
      ),
      isTrue,
    );
  });
}

StrokeBatchQueue _queue() => StrokeBatchQueue(
  sessionId: null,
  sender: null,
  policy: const DrawingSyncPolicy(eventThreshold: 100),
  now: () => DateTime.utc(2026, 7, 22, 1, 2, 3),
);

List<StrokeEventDto> _stroke({
  required int startSeq,
  required int endSeq,
  required int startTime,
  String tool = 'PEN',
  String? color = '#E35D6A',
  double width = 8,
  double? startPressure,
  double? endPressure,
}) {
  final moveSeq = endSeq - startSeq > 1 ? startSeq + 1 : null;
  return [
    _pointEvent(
      seq: startSeq,
      t: startTime,
      type: 'STROKE_START',
      x: 0.1,
      y: 0.2,
      includeStyle: true,
      tool: tool,
      color: color,
      width: width,
      pressure: startPressure,
    ),
    if (moveSeq != null)
      _pointEvent(
        seq: moveSeq,
        t: startTime + 10,
        type: 'STROKE_MOVE',
        x: 0.2,
        y: 0.3,
      ),
    _pointEvent(
      seq: endSeq,
      t: startTime + 20,
      type: 'STROKE_END',
      x: 0.3,
      y: 0.4,
      pressure: endPressure,
    ),
  ];
}

StrokeEventDto _pointEvent({
  required int seq,
  required int t,
  required String type,
  required double x,
  required double y,
  double? pressure,
  bool includeStyle = false,
  String tool = 'PEN',
  String? color = '#E35D6A',
  double width = 8,
}) => StrokeEventDto(
  seq: seq,
  t: t,
  type: type,
  x: x,
  y: y,
  tool: includeStyle ? tool : null,
  color: includeStyle ? color : null,
  thickness: includeStyle ? width : null,
  pressure: pressure,
);

StrokeBatchResponseDto _response(StrokeBatchRequestDto request) =>
    StrokeBatchResponseDto(
      batchId: 1,
      batchSequence: request.batchSequence,
      acceptedEventCount: request.events.length,
      lastEventSequence: request.lastEventSequence,
      receivedAt: '2026-07-22T01:02:03Z',
    );
