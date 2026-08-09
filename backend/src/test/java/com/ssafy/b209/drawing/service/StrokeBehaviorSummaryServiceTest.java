package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.drawing.document.StrokeBatchDocument;
import com.ssafy.b209.drawing.document.StrokeEventDocument;
import com.ssafy.b209.drawing.document.StrokePointDocument;
import com.ssafy.b209.drawing.repository.StrokeBatchDocumentRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

class StrokeBehaviorSummaryServiceTest {

  private static final Long SESSION_ID = 100L;
  private static final Instant BASE = Instant.parse("2026-08-03T01:00:00Z");

  private final StrokeBatchDocumentRepository repository =
      mock(StrokeBatchDocumentRepository.class);
  private final StrokeBehaviorSummaryService service = new StrokeBehaviorSummaryService(repository);

  @Test
  void returnsEmptyWhenSessionHasNoStrokeBatch() {
    givenBatches(List.of());

    assertThat(service.summarize(SESSION_ID)).isEmpty();
  }

  @Test
  void doesNotQueryStorageWithoutSession() {
    assertThat(service.summarize(null)).isEmpty();

    verifyNoInteractions(repository);
  }

  @Test
  void measuresSingleStrokeFromItsFirstAndLastPoint() {
    givenBatches(batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 300, 800)));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.activeDrawingMs()).isEqualTo(800L);
    // 배치가 하나뿐이라 배치 사이 간격이 없다. 실제 입력 시간이 전체 시간의 하한이 된다.
    assertThat(summary.drawingDurationMs()).isEqualTo(800L);
    assertThat(summary.pauseCount()).isZero();
    assertThat(summary.undoCount()).isZero();
    assertThat(summary.eraseCount()).isZero();
    assertThat(summary.toolChangeCount()).isZero();
    assertThat(summary.colorChangeCount()).isZero();
    assertThat(summary.pressureAvailable()).isFalse();
  }

  @Test
  void sumsActiveTimeOfEveryStrokeAcrossBatches() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 1000)),
        batch(2, BASE.plusMillis(3_000), stroke(2, "PEN", "#FF0000", 0, 1000)),
        batch(3, BASE.plusMillis(6_000), stroke(3, "PEN", "#FF0000", 0, 1000)));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.activeDrawingMs()).isEqualTo(3_000L);
    // 첫 배치와 마지막 배치 생성 시각의 간격.
    assertThat(summary.drawingDurationMs()).isEqualTo(6_000L);
  }

  @Test
  void ordersBatchesByBatchSequenceNotByStorageOrder() {
    givenBatches(
        batch(3, BASE.plusMillis(6_000), stroke(3, "ERASER", null, 0, 100)),
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 100)),
        batch(2, BASE.plusMillis(3_000), stroke(2, "PEN", "#00FF00", 0, 100)));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.drawingDurationMs()).isEqualTo(6_000L);
    assertThat(summary.toolChangeCount()).isEqualTo(1);
    assertThat(summary.colorChangeCount()).isEqualTo(1);
  }

  @Test
  void ordersEventsWithinBatchByStrokeSequence() {
    givenBatches(
        batch(
            1,
            BASE,
            stroke(3, "PEN", "#0000FF", 0, 100),
            stroke(1, "PEN", "#FF0000", 0, 100),
            stroke(2, "ERASER", null, 0, 100)));

    StrokeBehaviorSummary summary = summarize();

    // 순번 순서 PEN → ERASER → PEN 이므로 도구는 두 번 바뀐다. 저장 순서대로 읽으면 한 번으로 잘못 센다.
    assertThat(summary.toolChangeCount()).isEqualTo(2);
    assertThat(summary.colorChangeCount()).isEqualTo(1);
    assertThat(summary.eraseCount()).isEqualTo(1);
  }

  @Test
  void countsNoChangeWhenToolAndColorStayTheSame() {
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            stroke(2, "PEN", "#FF0000", 0, 100),
            stroke(3, "PEN", "#FF0000", 0, 100)));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.toolChangeCount()).isZero();
    assertThat(summary.colorChangeCount()).isZero();
  }

  @Test
  void countsEveryAlternationOfToolAndColor() {
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            stroke(2, "PEN", "#00FF00", 0, 100),
            stroke(3, "PEN", "#FF0000", 0, 100)));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.colorChangeCount()).isEqualTo(2);
    assertThat(summary.toolChangeCount()).isZero();
  }

  @Test
  void doesNotTreatColorlessEraserStrokeAsColorChange() {
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            stroke(2, "ERASER", null, 0, 100),
            stroke(3, "PEN", "#FF0000", 0, 100)));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.colorChangeCount()).isZero();
    assertThat(summary.toolChangeCount()).isEqualTo(2);
  }

  @Test
  void countsUndoEventsAndIgnoresRedo() {
    givenBatches(batch(1, BASE, marker(1, "UNDO"), marker(2, "REDO"), marker(3, "UNDO")));

    StrokeBehaviorSummary summary = summarize();

    // REDO 로 되돌렸다고 UNDO 를 빼지 않는다. 되돌린 행동 자체가 관찰값이다.
    assertThat(summary.undoCount()).isEqualTo(2);
    assertThat(summary.activeDrawingMs()).isZero();
    assertThat(summary.drawingDurationMs()).isZero();
  }

  @Test
  void countsEraserStrokesWhenNoExplicitEraseEventArrives() {
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "ERASER", null, 0, 100),
            stroke(2, "ERASER", null, 0, 100),
            stroke(3, "PEN", "#FF0000", 0, 100)));

    assertThat(summarize().eraseCount()).isEqualTo(2);
  }

  @Test
  void countsOnlyExplicitEraseEventsWhenTheyArriveAlongsideEraserStrokes() {
    // 지우개 획과 ERASE 이벤트를 함께 세면 한 번의 지우기가 두 번 잡혀 수치가 두 배가 된다.
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "ERASER", null, 0, 100),
            marker(2, "ERASE"),
            stroke(3, "PEN", "#FF0000", 0, 100)));

    assertThat(summarize().eraseCount()).isEqualTo(1);
  }

  @Test
  void countsOnlyExplicitToolChangeEventsWhenTheyArrive() {
    // 앱이 TOOL_CHANGE 를 보내면서 획의 tool 도 바꿔 실으면, 한 번의 도구 변경이 양쪽에서 잡힌다.
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            marker(2, "TOOL_CHANGE"),
            stroke(3, "ERASER", null, 0, 100)));

    assertThat(summarize().toolChangeCount()).isEqualTo(1);
  }

  @Test
  void countsOnlyExplicitColorChangeEventsWhenTheyArrive() {
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            marker(2, "COLOR_CHANGE"),
            stroke(3, "PEN", "#00FF00", 0, 100)));

    assertThat(summarize().colorChangeCount()).isEqualTo(1);
  }

  @Test
  void countsExplicitPauseEventsInsteadOfInferringFromBatchBoundaries() {
    // 배치 경계 추론은 flush 시점 오차 때문에 없던 멈춤까지 만든다. 아래는 경계가 둘이라 추론이면 2회로 잡히지만,
    //   앱이 실제로 알린 멈춤은 1회다. PAUSE 가 오면 추론을 끄고 그것만 센다.
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 0), marker(2, "PAUSE")),
        batch(2, BASE.plusMillis(60_000), stroke(3, "PEN", "#FF0000", 0, 0)),
        batch(3, BASE.plusMillis(120_000), stroke(4, "PEN", "#FF0000", 0, 0)));

    assertThat(summarize().pauseCount()).isEqualTo(1);
  }

  @Test
  void appliesExplicitCountingToTheWholeSessionNotJustTheBatchThatCarriesTheEvent() {
    // 배치 단위로 판단하면 첫 배치는 추론(도구 변경 1회), 둘째 배치는 명시로 세어 기준이 갈린다.
    //   세션 하나의 수치는 하나의 기준으로 세야 한다.
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            stroke(2, "ERASER", null, 0, 100),
            stroke(3, "PEN", "#FF0000", 0, 100)),
        batch(2, BASE.plusMillis(1_000), marker(4, "TOOL_CHANGE")));

    assertThat(summarize().toolChangeCount()).isEqualTo(1);
  }

  @Test
  void ignoresEventTypesThatHaveNoFieldToLandIn() {
    // REDO·RESUME·THICKNESS_CHANGE·CANVAS_CLEAR·FILL 은 담을 자리가 없다. 다른 수치를 흔들어서는 안 된다.
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            marker(2, "REDO"),
            marker(3, "RESUME"),
            marker(4, "THICKNESS_CHANGE"),
            marker(5, "CANVAS_CLEAR"),
            marker(6, "FILL")));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.undoCount()).isZero();
    assertThat(summary.eraseCount()).isZero();
    assertThat(summary.toolChangeCount()).isZero();
    assertThat(summary.colorChangeCount()).isZero();
    assertThat(summary.pauseCount()).isZero();
    assertThat(summary.activeDrawingMs()).isEqualTo(100L);
  }

  @Test
  void keepsInferringForEventTypesTheSessionNeverSent() {
    // 구버전 앱과 신버전 앱이 함께 붙어 있는 기간이 있다. 한 종류가 왔다고 나머지 추론까지 끄면
    //   그 종류를 보내지 않는 클라이언트의 수치가 통째로 0이 된다.
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            marker(2, "TOOL_CHANGE"),
            stroke(3, "PEN", "#00FF00", 0, 100)));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.toolChangeCount()).isEqualTo(1);
    // COLOR_CHANGE 는 오지 않았으므로 색 변경은 계속 획 속성으로 추론한다.
    assertThat(summary.colorChangeCount()).isEqualTo(1);
  }

  @Test
  void doesNotCountIdleShorterThanPauseThreshold() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 0)),
        batch(2, BASE.plusMillis(2_999), stroke(2, "PEN", "#FF0000", 0, 0)));

    assertThat(summarize().pauseCount()).isZero();
  }

  @Test
  void countsIdleExactlyAtPauseThreshold() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 0)),
        batch(2, BASE.plusMillis(3_000), stroke(2, "PEN", "#FF0000", 0, 0)));

    assertThat(summarize().pauseCount()).isEqualTo(1);
  }

  @Test
  void countsIdleAbovePauseThreshold() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 0)),
        batch(2, BASE.plusMillis(3_001), stroke(2, "PEN", "#FF0000", 0, 0)));

    assertThat(summarize().pauseCount()).isEqualTo(1);
  }

  @Test
  void subtractsDrawingTimeFromBatchGapBeforeJudgingPause() {
    // 배치 간격은 5초지만 그 사이 2001ms 를 실제로 그렸다. 멈춘 시간은 2999ms 라 멈춤이 아니다.
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 0)),
        batch(2, BASE.plusMillis(5_000), stroke(2, "PEN", "#FF0000", 0, 2_001)));

    assertThat(summarize().pauseCount()).isZero();
  }

  @Test
  void countsPauseWhenIdleRemainsAfterSubtractingDrawingTime() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 0)),
        batch(2, BASE.plusMillis(5_000), stroke(2, "PEN", "#FF0000", 0, 2_000)));

    assertThat(summarize().pauseCount()).isEqualTo(1);
  }

  @Test
  void countsPauseAtEveryBatchBoundaryThatExceedsThreshold() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 0)),
        batch(2, BASE.plusMillis(4_000), stroke(2, "PEN", "#FF0000", 0, 0)),
        batch(3, BASE.plusMillis(8_000), stroke(3, "PEN", "#FF0000", 0, 0)));

    assertThat(summarize().pauseCount()).isEqualTo(2);
  }

  @Test
  void countsGapJustUnderInterruptionLimitAsDrawingTime() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 0)),
        batch(2, BASE.plusMillis(299_999), stroke(2, "PEN", "#FF0000", 0, 0)));

    assertThat(summarize().drawingDurationMs()).isEqualTo(299_999L);
  }

  @Test
  void countsGapExactlyAtInterruptionLimitAsDrawingTime() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 0)),
        batch(2, BASE.plusMillis(300_000), stroke(2, "PEN", "#FF0000", 0, 0)));

    assertThat(summarize().drawingDurationMs()).isEqualTo(300_000L);
  }

  @Test
  void excludesGapAboveInterruptionLimitFromDrawingTime() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 400)),
        batch(2, BASE.plusMillis(300_001), stroke(2, "PEN", "#FF0000", 0, 400)));

    // 중단 후 재개로 보고 간격을 빼면 남는 것은 실제로 그린 800ms 뿐이다.
    assertThat(summarize().drawingDurationMs()).isEqualTo(800L);
  }

  @Test
  void excludesOnlyTheInterruptedGapAndKeepsContinuousOnes() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 0)),
        batch(2, BASE.plusMillis(10_000), stroke(2, "PEN", "#FF0000", 0, 0)),
        // 앱을 12시간 떠났다가 이어 그린 배치.
        batch(3, BASE.plusMillis(43_210_000L), stroke(3, "PEN", "#FF0000", 0, 0)),
        batch(4, BASE.plusMillis(43_215_000L), stroke(4, "PEN", "#FF0000", 0, 0)));

    assertThat(summarize().drawingDurationMs()).isEqualTo(15_000L);
  }

  @Test
  void treatsSameColorWithDifferentHexCaseAsNoChange() {
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#ff0000", 0, 100),
            stroke(2, "PEN", "#FF0000", 0, 100),
            stroke(3, "PEN", "#Ff0000", 0, 100)));

    assertThat(summarize().colorChangeCount()).isZero();
  }

  @Test
  void skipsStrokeWithoutToolWhenCountingToolChanges() {
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            stroke(2, null, "#FF0000", 0, 100),
            stroke(3, "PEN", "#FF0000", 0, 100)));

    assertThat(summarize().toolChangeCount()).isZero();
  }

  @Test
  void ignoresBatchWithoutClientCreatedAtWhenMeasuringTime() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 100)),
        batch(2, null, stroke(2, "PEN", "#FF0000", 0, 100)),
        batch(3, BASE.plusMillis(4_000), stroke(3, "PEN", "#FF0000", 0, 100)));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.drawingDurationMs()).isEqualTo(4_000L);
    // 시각을 모르는 배치는 경계 판정에서 건너뛰고 직전 시각을 유지한다. 4000 - 100(batch3 활동) = 3900 >= 3000.
    assertThat(summary.pauseCount()).isEqualTo(1);
    assertThat(summary.activeDrawingMs()).isEqualTo(300L);
  }

  @Test
  void treatsStrokeWithoutPointsAsZeroDrawingTime() {
    givenBatches(
        batch(
            1,
            BASE,
            new StrokeEventDocument(
                1, "STROKE", "PEN", "#FF0000", new BigDecimal("8.0"), null, List.of())));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.activeDrawingMs()).isZero();
    assertThat(summary.drawingDurationMs()).isZero();
  }

  @Test
  void requestsBatchesOrderedByBatchSequenceWithOneMoreThanTheLimit() {
    givenBatches(List.of(batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 100))));

    service.summarize(SESSION_ID);

    ArgumentCaptor<Pageable> captor = ArgumentCaptor.forClass(Pageable.class);
    verify(repository).findBehaviorAggregationInputs(eq(SESSION_ID), captor.capture());
    Pageable pageable = captor.getValue();
    // 상한 + 1 을 요청해야 별도 count 조회 없이 절단 여부를 알 수 있다.
    assertThat(pageable.getPageSize())
        .isEqualTo(StrokeBehaviorSummaryService.MAX_AGGREGATED_BATCHES + 1);
    assertThat(pageable.getSort()).isEqualTo(Sort.by(Sort.Direction.ASC, "batchSeq"));
  }

  @Test
  void doesNotMarkTruncatedWhenBatchCountIsExactlyAtTheLimit() {
    givenBatches(batchesOf(StrokeBehaviorSummaryService.MAX_AGGREGATED_BATCHES));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.truncated()).isFalse();
    assertThat(summary.undoCount()).isEqualTo(StrokeBehaviorSummaryService.MAX_AGGREGATED_BATCHES);
  }

  @Test
  void marksTruncatedAndAggregatesOnlyTheLimitWhenBatchCountExceedsIt() {
    givenBatches(batchesOf(StrokeBehaviorSummaryService.MAX_AGGREGATED_BATCHES + 1));

    StrokeBehaviorSummary summary = summarize();

    // 조용히 자르면 하류가 전체를 본 값으로 읽는다. 부분 집계라는 사실이 값에 드러나야 한다.
    assertThat(summary.truncated()).isTrue();
    assertThat(summary.undoCount()).isEqualTo(StrokeBehaviorSummaryService.MAX_AGGREGATED_BATCHES);
  }

  @Test
  void reportsPressureUnavailableWhenNoPointCarriesIt() {
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 100, 200)),
        batch(2, BASE.plusMillis(1_000), stroke(2, "PEN", "#FF0000", 0, 100)));

    assertThat(summarize().pressureAvailable()).isFalse();
  }

  @Test
  void reportsPressureAvailableWhenAnySinglePointCarriesIt() {
    StrokeEventDocument withPressure =
        new StrokeEventDocument(
            2,
            "STROKE",
            "PEN",
            "#FF0000",
            new BigDecimal("8.0"),
            null,
            List.of(point(0, null), point(100, null), point(200, new BigDecimal("0.42"))));
    givenBatches(
        batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 100)),
        batch(2, BASE.plusMillis(1_000), withPressure));

    assertThat(summarize().pressureAvailable()).isTrue();
  }

  @Test
  void treatsZeroPressureAsAvailableMeasurement() {
    StrokeEventDocument zeroPressure =
        new StrokeEventDocument(
            1,
            "STROKE",
            "PEN",
            "#FF0000",
            new BigDecimal("8.0"),
            null,
            List.of(point(0, BigDecimal.ZERO), point(100, BigDecimal.ZERO)));
    givenBatches(batch(1, BASE, zeroPressure));

    assertThat(summarize().pressureAvailable()).isTrue();
  }

  private StrokeBehaviorSummary summarize() {
    Optional<StrokeBehaviorSummary> summary = service.summarize(SESSION_ID);
    assertThat(summary).isPresent();
    return summary.get();
  }

  @Test
  void summarizeAllSumsCountsAndOrsFlagsAcrossSessions() {
    // HTP 리포트 하나는 집·나무·사람 세 활동을 다룬다. 세션 하나만 쓰면 보호자가 보는 수치가 3분의 1로 줄어든다
    // (S15P11B209-870).
    givenBatchesFor(101L, batch(1, BASE, marker(1, "ERASE")));
    givenBatchesFor(102L, batch(1, BASE, marker(1, "UNDO")));
    givenBatchesFor(103L, List.of());

    StrokeBehaviorSummary summary = service.summarizeAll(List.of(101L, 102L, 103L)).orElseThrow();

    assertThat(summary.eraseCount()).isEqualTo(1);
    assertThat(summary.undoCount()).isEqualTo(1);
    assertThat(summary.truncated()).isFalse();
  }

  @Test
  void summarizeAllReturnsEmptyWhenEverySessionHasNoBatch() {
    givenBatchesFor(101L, List.of());
    givenBatchesFor(102L, List.of());

    assertThat(service.summarizeAll(List.of(101L, 102L))).isEmpty();
  }

  @Test
  void summarizeAllIgnoresNullAndDuplicateSessionIds() {
    givenBatchesFor(101L, batch(1, BASE, marker(1, "ERASE")));

    StrokeBehaviorSummary summary =
        service.summarizeAll(Arrays.asList(101L, null, 101L)).orElseThrow();

    // 같은 세션을 두 번 세면 수치가 두 배가 된다.
    assertThat(summary.eraseCount()).isEqualTo(1);
  }

  @Test
  void summarizeAllRejectsNothingToAggregate() {
    assertThat(service.summarizeAll(null)).isEmpty();
    assertThat(service.summarizeAll(List.of())).isEmpty();
  }

  @Test
  void summarizeAllOrNoneDropsEverythingWhenOneSessionCannotBeAggregated() {
    // HTP 한 단계가 사진 업로드라 캔버스 과정이 없거나 배치가 유실되면, 두 단계만 더한 합이
    //   "이 활동 전체의 기록"으로 AI 프롬프트에 실린다. AI 는 그 수치를 관찰 사실로 문장에 옮긴다.
    givenBatchesFor(101L, batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 100)));
    givenBatchesFor(102L, batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 100)));
    givenBatchesFor(103L, List.of());

    assertThat(service.summarizeAllOrNone(List.of(101L, 102L, 103L))).isEmpty();
  }

  @Test
  void summarizeAllOrNoneSumsWhenEverySessionAggregates() {
    givenBatchesFor(101L, batch(1, BASE, marker(1, "ERASE")));
    givenBatchesFor(102L, batch(1, BASE, marker(1, "UNDO")));

    StrokeBehaviorSummary summary = service.summarizeAllOrNone(List.of(101L, 102L)).orElseThrow();

    assertThat(summary.eraseCount()).isEqualTo(1);
    assertThat(summary.undoCount()).isEqualTo(1);
  }

  @Test
  void summarizeAllOrNoneIgnoresNullAndDuplicateSessionIds() {
    givenBatchesFor(101L, batch(1, BASE, marker(1, "ERASE")));

    StrokeBehaviorSummary summary =
        service.summarizeAllOrNone(Arrays.asList(101L, null, 101L)).orElseThrow();

    assertThat(summary.eraseCount()).isEqualTo(1);
  }

  @Test
  void summarizeAllOrNoneRejectsNothingToAggregate() {
    assertThat(service.summarizeAllOrNone(null)).isEmpty();
    assertThat(service.summarizeAllOrNone(List.of())).isEmpty();
  }

  @Test
  void countsEveryStrokeIncludingEraserStrokes() {
    // 지우개로 긋는 것도 획이다. 도구로 세는 대상을 가르면 "전체 획 수"가 아니게 된다.
    //   그래서 eraseCount 와 겹치며, 두 값으로 비율을 만들면 안 된다는 것이 계약의 규칙이다.
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            stroke(2, "PEN", "#FF0000", 0, 100),
            stroke(3, "ERASER", null, 0, 100)));

    StrokeBehaviorSummary summary = summarize();

    assertThat(summary.strokeCount()).isEqualTo(3);
    assertThat(summary.eraseCount()).isEqualTo(1);
  }

  @Test
  void collectsColorsActuallyDrawnWithAsACaseInsensitiveSet() {
    // 계약의 색 정규식이 소문자 hex 도 허용해 #FF0000 과 #ff0000 이 섞여 들어온다. 정규화하지 않으면
    //   같은 색이 두 가지로 세어진다(colorChangeCount 가 대소문자를 무시하는 것과 같은 이유).
    givenBatches(
        batch(
            1,
            BASE,
            stroke(1, "PEN", "#FF0000", 0, 100),
            stroke(2, "PEN", "#ff0000", 0, 100),
            stroke(3, "PEN", "#00FF00", 0, 100),
            // 지우개 획은 색을 싣지 않는다 — 색 가짓수에 들어가면 안 된다.
            stroke(4, "ERASER", null, 0, 100)));

    assertThat(summarize().colorsUsed()).containsExactlyInAnyOrder("#ff0000", "#00ff00");
  }

  @Test
  void bySubjectLabelsEachSessionDurationWithItsSubject() {
    // 🔴 이 이슈의 핵심. 합계만으로는 "어느 그림에 더 오래 머물렀는가"를 말할 수 없다.
    givenBatchesFor(101L, batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 5_000)));
    givenBatchesFor(102L, batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 3_000)));
    givenBatchesFor(103L, batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 1_000)));

    StrokeBehaviorAggregate aggregate =
        service
            .summarizeAllOrNoneBySubject(
                List.of(
                    new SubjectStrokeSession(101L, "HOUSE"),
                    new SubjectStrokeSession(102L, "TREE"),
                    new SubjectStrokeSession(103L, "PERSON")))
            .orElseThrow();

    assertThat(aggregate.subjectDurations())
        .extracting(
            StrokeBehaviorAggregate.SubjectDuration::drawingSubject,
            StrokeBehaviorAggregate.SubjectDuration::activeDrawingMs)
        .containsExactly(
            org.assertj.core.api.Assertions.tuple("HOUSE", 5_000L),
            org.assertj.core.api.Assertions.tuple("TREE", 3_000L),
            org.assertj.core.api.Assertions.tuple("PERSON", 1_000L));
    // 합계는 그대로 세 세션의 합이다 — 주제별 내역이 합계를 대체하지 않는다.
    assertThat(aggregate.total().activeDrawingMs()).isEqualTo(9_000L);
  }

  @Test
  void bySubjectDropsSubjectDurationsTooWhenOneSessionCannotBeAggregated() {
    // 🔴 한 주제가 사진 업로드면 "집을 그릴 때 가장 오래 머물렀어요" 같은 비교 관찰이 거짓이 된다.
    //   부분 목록이 만들어질 수 없도록 합계와 내역을 함께 버린다.
    givenBatchesFor(101L, batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 5_000)));
    givenBatchesFor(102L, batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 3_000)));
    givenBatchesFor(103L, List.of());

    assertThat(
            service.summarizeAllOrNoneBySubject(
                List.of(
                    new SubjectStrokeSession(101L, "HOUSE"),
                    new SubjectStrokeSession(102L, "TREE"),
                    new SubjectStrokeSession(103L, "PERSON"))))
        .isEmpty();
  }

  @Test
  void bySubjectLeavesSubjectDurationsEmptyWhenTheActivityHasNoSubject() {
    // 그림일기는 주제 구분이 없다. 이름 없는 시간은 비교에 쓸 수 없고 합계에 이미 들어 있다.
    givenBatchesFor(101L, batch(1, BASE, stroke(1, "PEN", "#FF0000", 0, 5_000)));

    StrokeBehaviorAggregate aggregate =
        service
            .summarizeAllOrNoneBySubject(List.of(new SubjectStrokeSession(101L, null)))
            .orElseThrow();

    assertThat(aggregate.subjectDurations()).isEmpty();
    assertThat(aggregate.total().activeDrawingMs()).isEqualTo(5_000L);
  }

  @Test
  void summarizeAllStillSkipsEmptySessionsForTheGuardianReport() {
    // 보호자 화면은 일부라도 보여 주는 편이 낫다(S15P11B209-870). AI 경로와 의도적으로 다르다.
    givenBatchesFor(101L, batch(1, BASE, marker(1, "ERASE")));
    givenBatchesFor(102L, List.of());

    assertThat(service.summarizeAll(List.of(101L, 102L)).orElseThrow().eraseCount()).isEqualTo(1);
  }

  @Test
  void mergeKeepsNullWhenOneSessionDidNotMeasureThatValue() {
    // 🔴 null 을 0으로 바꿔 더하면 "측정하지 못한 세션"이 "0회인 세션"으로 둔갑하고,
    //   나머지 세션 값만으로 만든 합이 전체 합인 것처럼 나간다. 모르는 값은 더할 수 없다.
    StrokeBehaviorSummary measured =
        new StrokeBehaviorSummary(
            1_000L, 500L, 10, 2, 1, 3, 4, 5, Set.of("#ff0000", "#00ff00"), true, false);
    StrokeBehaviorSummary partly =
        new StrokeBehaviorSummary(1_000L, null, null, null, 1, 3, 4, 5, null, false, false);

    StrokeBehaviorSummary merged =
        StrokeBehaviorSummaryService.merge(List.of(measured, partly)).orElseThrow();

    assertThat(merged.drawingDurationMs()).isEqualTo(2_000L);
    assertThat(merged.activeDrawingMs()).isNull();
    assertThat(merged.pauseCount()).isNull();
    assertThat(merged.undoCount()).isEqualTo(2);
    assertThat(merged.strokeCount()).isNull();
    // 한 세션의 색을 모르면 합집합의 가짓수도 알 수 없다 — 아는 세션의 색만으로 세면
    //   그 가짓수가 활동 전체의 가짓수인 것처럼 나간다.
    assertThat(merged.colorsUsed()).isNull();
    // 한 세션에서라도 필압이 저장돼 있으면 필압 데이터는 존재한다.
    assertThat(merged.pressureAvailable()).isTrue();
  }

  @Test
  void mergeUnionsColorsInsteadOfAddingThePerSessionCounts() {
    // 🔴 색은 세션 경계에서 겹친다. 세션별 '가짓수'를 더하면 집·나무·사람 세 장에 모두 쓴 빨강이
    //   3가지로 계수돼, 세 가지 색을 쓴 활동이 "다섯 가지 색을 썼다"가 된다. 합집합이어야 한다.
    StrokeBehaviorSummary house =
        new StrokeBehaviorSummary(
            1L, 1L, 3, 0, 0, 0, 0, 0, Set.of("#ff0000", "#00ff00"), false, false);
    StrokeBehaviorSummary tree =
        new StrokeBehaviorSummary(
            1L, 1L, 3, 0, 0, 0, 0, 0, Set.of("#ff0000", "#0000ff"), false, false);
    StrokeBehaviorSummary person =
        new StrokeBehaviorSummary(1L, 1L, 3, 0, 0, 0, 0, 0, Set.of("#ff0000"), false, false);

    StrokeBehaviorSummary merged =
        StrokeBehaviorSummaryService.merge(List.of(house, tree, person)).orElseThrow();

    assertThat(merged.colorsUsed()).containsExactlyInAnyOrder("#ff0000", "#00ff00", "#0000ff");
    // 획 수는 세션끼리 겹치지 않는 값이라 그대로 더한다 — 합치는 규칙이 값의 성격마다 다르다는 것이 요점이다.
    assertThat(merged.strokeCount()).isEqualTo(9);
  }

  @Test
  void mergeMarksTheWholeSumTruncatedWhenAnySessionWasTruncated() {
    StrokeBehaviorSummary whole =
        new StrokeBehaviorSummary(1L, 1L, 0, 0, 0, 0, 0, 0, Set.of(), false, false);
    StrokeBehaviorSummary cut =
        new StrokeBehaviorSummary(1L, 1L, 0, 0, 0, 0, 0, 0, Set.of(), false, true);

    assertThat(StrokeBehaviorSummaryService.merge(List.of(whole, cut)).orElseThrow().truncated())
        .isTrue();
  }

  private void givenBatchesFor(Long sessionId, StrokeBatchDocument... batches) {
    givenBatchesFor(sessionId, List.of(batches));
  }

  private void givenBatchesFor(Long sessionId, List<StrokeBatchDocument> batches) {
    when(repository.findBehaviorAggregationInputs(eq(sessionId), any(Pageable.class)))
        .thenReturn(batches);
  }

  private void givenBatches(StrokeBatchDocument... batches) {
    givenBatches(List.of(batches));
  }

  private void givenBatches(List<StrokeBatchDocument> batches) {
    when(repository.findBehaviorAggregationInputs(eq(SESSION_ID), any(Pageable.class)))
        .thenReturn(batches);
  }

  /** 배치 하나마다 UNDO 하나만 담아, 집계된 배치 수를 {@code undoCount} 로 셀 수 있게 한다. */
  private static List<StrokeBatchDocument> batchesOf(int count) {
    return IntStream.rangeClosed(1, count)
        .mapToObj(seq -> batch(seq, BASE.plusMillis(seq * 3_000L), marker(seq, "UNDO")))
        .toList();
  }

  private static StrokeBatchDocument batch(
      int batchSeq, Instant clientCreatedAt, StrokeEventDocument... strokes) {
    List<StrokeEventDocument> events = List.of(strokes);
    return new StrokeBatchDocument(
        (long) batchSeq,
        SESSION_ID,
        7L,
        batchSeq,
        events.isEmpty() ? 0 : events.getFirst().strokeSeq(),
        events.isEmpty() ? 0 : events.getLast().strokeSeq(),
        events.size(),
        events.stream().mapToInt(event -> event.points().size()).sum(),
        "checksum-" + batchSeq,
        0,
        0,
        0,
        0,
        clientCreatedAt,
        BASE,
        BASE,
        BASE.plusSeconds(60),
        events);
  }

  private static StrokeEventDocument stroke(
      long strokeSeq, String tool, String color, long... pointTimes) {
    List<StrokePointDocument> points = new ArrayList<>(pointTimes.length);
    for (long pointTime : pointTimes) {
      points.add(point(pointTime, null));
    }
    return new StrokeEventDocument(
        strokeSeq, "STROKE", tool, color, new BigDecimal("8.0"), null, List.copyOf(points));
  }

  private static StrokeEventDocument marker(long strokeSeq, String eventType) {
    return new StrokeEventDocument(strokeSeq, eventType, null, null, null, null, List.of());
  }

  private static StrokePointDocument point(long elapsedMs, BigDecimal pressure) {
    return new StrokePointDocument(
        new BigDecimal("0.5"), new BigDecimal("0.5"), elapsedMs, pressure);
  }
}
