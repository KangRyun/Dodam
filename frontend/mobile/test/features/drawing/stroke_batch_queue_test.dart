import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('batchSequence와 event 범위를 계산하고 불변 payload를 만든다', () async {
    final queue = StrokeBatchQueue(
      sessionId: null,
      sender: null,
      policy: const DrawingSyncPolicy(eventThreshold: 100),
      now: () => DateTime.utc(2026, 7, 22, 1, 2, 3),
    );
    queue.addEvents([_event(11), _event(12), _event(13)]);
    await queue.flush();
    queue.addEvents([_event(14)]);
    await queue.flush();

    final first = queue.pendingBatches[0].request;
    final second = queue.pendingBatches[1].request;
    expect(first.batchSequence, 1);
    expect(first.firstEventSequence, 11);
    expect(first.lastEventSequence, 13);
    expect(first.toJson()['eventCount'], 3);
    expect(first.clientCreatedAt, '2026-07-22T01:02:03.000Z');
    expect(second.batchSequence, 2);
    expect(() => first.events.add(_event(99)), throwsUnsupportedError);
  });

  test('retry는 같은 batch 객체와 payload를 재사용한다', () async {
    final requests = <StrokeBatchRequestDto>[];
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
    );
    queue.addEvents([_event(1), _event(2)]);
    await queue.flush();
    final failedRequest = queue.pendingBatches.single.request;

    fail = false;
    await queue.retryHead();

    expect(requests, hasLength(2));
    expect(identical(requests[0], requests[1]), isTrue);
    expect(identical(requests[0], failedRequest), isTrue);
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
    queue.addEvents([_event(1), _event(2)]);
    await queue.flush();
    queue.addEvents([_event(3), _event(4)]);
    await queue.flush();
    queue.addEvents([_event(5)]);

    expect(calls, 1);
    expect(queue.pendingBatches, hasLength(2));
    expect(queue.bufferedEvents, hasLength(1));
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

StrokeEventDto _event(int seq) => StrokeEventDto(
  seq: seq,
  t: seq * 10,
  type: seq.isOdd ? 'STROKE_START' : 'STROKE_END',
  x: 0.2,
  y: 0.3,
);

StrokeBatchResponseDto _response(StrokeBatchRequestDto request) =>
    StrokeBatchResponseDto(
      strokeBatchId: 1,
      batchSequence: request.batchSequence,
      eventCount: request.events.length,
      receivedAt: '2026-07-22T01:02:03Z',
    );
