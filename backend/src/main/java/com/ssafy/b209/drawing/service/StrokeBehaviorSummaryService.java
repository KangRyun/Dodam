package com.ssafy.b209.drawing.service;

import com.ssafy.b209.drawing.document.StrokeBatchDocument;
import com.ssafy.b209.drawing.document.StrokeEventDocument;
import com.ssafy.b209.drawing.document.StrokePointDocument;
import com.ssafy.b209.drawing.repository.StrokeBatchDocumentRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;

/**
 * 한 그림 활동에 저장된 Stroke 배치를 읽어 행동 요약을 집계한다 (S15P11B209-772).
 *
 * <p><b>왜 배치 시각(clientCreatedAt)이 기준인가.</b> 좌표의 {@code elapsedMs}는 API 명세 §10.5가 정한 대로 <b>해당 STROKE
 * 이벤트가 시작한 시점</b> 기준 상대 시간이라 매 획마다 0에서 다시 시작한다. 즉 획과 획 사이를 이을 수 있는 시각 축이 아니다. 이벤트 문서에는 절대 시각 필드가 아예
 * 없고, 세션 전체를 관통하는 시각은 배치 문서의 {@code clientCreatedAt}(클라이언트가 배치를 만든 시각)과 {@code receivedAt}(서버 수신
 * 시각)뿐이다. 둘 중 {@code receivedAt}은 전송 실패 후 재시도하면 실제 그린 시각보다 한참 뒤로 밀리고 순서까지 뒤집히므로, 같은 기기의 단조 증가 시계로
 * 찍히는 {@code clientCreatedAt}을 쓴다. 배치 사이 시각 비교만 하므로 기기와 서버의 시계 차이는 상쇄된다.
 *
 * <p><b>정렬 기준은 {@code batchSeq}다.</b> 같은 이유로 수신 순서를 믿을 수 없다. 배치 순번은 클라이언트가 그린 순서대로 증가시키므로 이것이 유일한
 * 재생 순서다.
 *
 * <p><b>한계 — {@code pauseCount}는 추정값이며 상한도 하한도 아니다.</b> 한 배치 <i>안</i>의 획 사이 간격을 잴 수 없어 {@link
 * #PAUSE_THRESHOLD_MS} 규칙을 배치 경계에서만 적용하는데, 경계 시각인 {@code clientCreatedAt}은 "획이 끝난 시각"이 아니라 "flush가
 * 일어난 시각"이다. 여기서 오차가 세 방향으로 생긴다 (S15P11B209-772 QA 실측).
 *
 * <ul>
 *   <li><b>과다</b> — 획이 flush 주기를 가로지르면 미완결이라 그 배치에 실리지 못하고 다음 배치로 이월된다. 그러면 획의 앞뒤 flush 대기 시간이 유휴로
 *       계상돼, 실제로는 3초 이상 멈춘 적이 없는데도 멈춤 1회가 잡힐 수 있다. QA 재현: 유휴 5,000ms로 계산됐으나 실제 최장 무입력은 2,510ms
 *   <li><b>과소</b> — 멈춤의 앞부분이 직전 flush에 흡수되면 경계에서 재는 유휴가 실제보다 짧아진다. QA 재현: 실제 5,000ms 멈춤이 유휴
 *       2,500ms로 계산돼 집계되지 않음
 *   <li><b>접힘</b> — 한 경계 구간 안에 멈춤이 여러 번 있어도 1회로 접힌다
 * </ul>
 *
 * <p>정확히 세려면 FE가 {@code PAUSE} 이벤트를 보내거나 STROKE 이벤트에 절대 시각을 실어야 하며, 둘 다 계약 변경 사안이라 여기서 다루지 않는다. 값을
 * 쓰는 쪽은 "대략 이 정도로 멈췄다"는 지표로만 취급해야 한다.
 */
@Service
public class StrokeBehaviorSummaryService {

  /**
   * 이 시간 이상 입력이 없으면 멈춤 1회로 센다.
   *
   * <p>아동 그리기에서 3초는 "다음에 뭘 그릴지 생각하는 멈춤"으로 읽히는 길이이고, 획을 바꾸는 정도의 짧은 손놀림은 걸러내 오탐이 적다. 팀에서 확정한 값이다.
   */
  static final long PAUSE_THRESHOLD_MS = 3_000L;

  /**
   * 이 시간을 넘는 배치 간격은 그리기가 아니라 <b>활동 중단 후 재개</b>로 보고 전체 그림 시간에서 제외한다.
   *
   * <p>FE는 앱이 백그라운드로 가거나 모달이 열릴 때 배치를 flush한다({@code activity_screens.dart}). 그래서 아이가 앱을 닫고 자고 다음 날
   * 이어 그리면 같은 세션에 하루 간격의 배치 두 개가 남고, 상한이 없으면 {@code drawingDurationMs}가 12시간으로 나간다. 실제로 그린 시간이
   * 8분인데도 그렇다.
   *
   * <p><b>5분으로 정한 근거.</b> 상한은 "앱 안에서 망설이는 시간"의 최댓값보다는 크고 "앱을 떠난 시간"의 최솟값보다는 작아야 한다. 팀이 확정한 생각하는 멈춤은
   * 3초 규모이고({@link #PAUSE_THRESHOLD_MS}), 보호자와 이야기하거나 색을 고르며 멈추는 경우를 넉넉히 잡아도 분 단위를 넘기기 어렵다. 반대로 앱
   * 이탈은 대개 화면 전환·자리 비움이라 분 단위 아래로 끝나지 않는다. 5분은 그 사이에서 정상 활동을 자르지 않으면서 이탈을 걸러내는 값이다. 앱에 머무는 동안의 유휴를
   * 알려주는 신호(heartbeat)가 FE에 없어 이보다 정밀하게 나눌 수는 없다 — 실제 간격 분포는 S15P11B209-609에서 측정할 수 있다.
   *
   * <p>제외해도 {@code activeDrawingMs} 하한이 살아 있어 그린 시간이 사라지지는 않는다.
   */
  static final long MAX_CONTINUOUS_GAP_MS = 300_000L;

  /**
   * 한 번의 집계가 읽을 배치 수 상한이다.
   *
   * <p>배치 <b>크기</b>는 1 MiB로 막혀 있지만({@code StrokeBatchService}) 세션당 배치 <b>수</b>에는 제약이 없다. 이 집계는 AI
   * 호출 직전 동기 경로에서 일어나므로 결과 집합이 무제한이면 요청 스레드의 힙과 read timeout 예산을 함께 잠식하고, 그때 터지는 {@code
   * OutOfMemoryError}는 호출부의 {@code catch (RuntimeException)}에 걸리지도 않는다.
   *
   * <p>1,000개는 FE의 3초 flush 주기 기준 약 50분 분량이라 이어그리기를 포함한 정상 활동을 자르지 않는다. 이보다 많으면 비정상 클라이언트로 보고 앞부분만
   * 집계하되, {@link StrokeBehaviorSummary#truncated()}와 경고 로그로 <b>부분 집계임을 반드시 드러낸다.</b> 조용히 자르면 하류가
   * 전체를 본 값으로 읽는다.
   */
  static final int MAX_AGGREGATED_BATCHES = 1_000;

  /** 명세 §10.5에서 STROKE_START~STROKE_END를 하나로 집약한 이벤트 코드다. */
  private static final String STROKE_EVENT_TYPE = "STROKE";

  /** 명세 §10.5의 독립 실행 취소 이벤트 코드다. */
  private static final String UNDO_EVENT_TYPE = "UNDO";

  /**
   * 명세 §10.5가 독립 이벤트로 정의한 지우기 코드다.
   *
   * <p>현재 앱은 이 이벤트를 보내지 않고 지우개 획을 {@code tool=ERASER}인 STROKE로 보낸다. 두 형태를 모두 세어 계약과 실제 전송을 함께
   * 만족시킨다.
   *
   * <p>⚠️ FE가 장차 지우개 획과 {@code ERASE} 이벤트를 <b>함께</b> 보내기 시작하면 같은 행동이 양쪽에서 세어져 {@code eraseCount}가 두
   * 배가 된다. 그때는 둘 중 한쪽만 세도록 고쳐야 한다.
   */
  private static final String ERASE_EVENT_TYPE = "ERASE";

  /** 앱이 지우개 획에 실어 보내는 도구 코드다. */
  private static final String ERASER_TOOL = "ERASER";

  /** 정렬 키로 쓰는 배치 순번의 문서 필드 이름이다. */
  private static final String BATCH_SEQ_FIELD = "batchSeq";

  private static final Logger log = LoggerFactory.getLogger(StrokeBehaviorSummaryService.class);

  private final StrokeBatchDocumentRepository strokeBatchDocumentRepository;

  /**
   * 집계에 필요한 Stroke 배치 Repository를 주입받는다.
   *
   * @param strokeBatchDocumentRepository Stroke 배치 문서 Repository
   */
  public StrokeBehaviorSummaryService(StrokeBatchDocumentRepository strokeBatchDocumentRepository) {
    this.strokeBatchDocumentRepository = strokeBatchDocumentRepository;
  }

  /**
   * 한 그림 활동의 저장된 Stroke 배치에서 행동 요약을 집계한다.
   *
   * <p>저장된 배치가 하나도 없으면 빈 값을 돌려준다. 외부에서 업로드한 그림처럼 캔버스 과정 자체가 없는 활동에 0으로 채운 요약을 만들어 붙이지 않기 위해서다.
   *
   * <p>Transaction을 열지 않는다. 읽는 곳이 MongoDB 하나이고 리포에 {@code MongoTransactionManager} 빈이 없어,
   * {@code @Transactional}을 붙이면 Mongo 읽기와 아무 상관 없는 JPA Transaction만 새로 열린다.
   *
   * <p>상한보다 한 건 더 요청해 절단 여부를 별도 count 조회 없이 판별한다.
   *
   * @param drawingSessionId 그림 활동 식별자
   * @return 집계된 행동 요약, 저장된 배치가 없으면 빈 값
   */
  public Optional<StrokeBehaviorSummary> summarize(Long drawingSessionId) {
    if (drawingSessionId == null) {
      return Optional.empty();
    }
    List<StrokeBatchDocument> batches =
        strokeBatchDocumentRepository.findBehaviorAggregationInputs(
            drawingSessionId,
            PageRequest.of(
                0, MAX_AGGREGATED_BATCHES + 1, Sort.by(Sort.Direction.ASC, BATCH_SEQ_FIELD)));
    if (batches.size() > MAX_AGGREGATED_BATCHES) {
      log.warn(
          "[772] 세션의 Stroke 배치가 집계 상한을 넘어 앞부분만 집계한다: drawingSessionId={}, limit={}",
          drawingSessionId,
          MAX_AGGREGATED_BATCHES);
      return aggregate(batches.subList(0, MAX_AGGREGATED_BATCHES), true);
    }
    return aggregate(batches, false);
  }

  /**
   * 여러 세션의 행동 요약을 하나로 합친다 (S15P11B209-870).
   *
   * <p>HTP 리포트 하나는 집·나무·사람 <b>세 활동</b>을 함께 다룬다. 그래서 리포트에 실을 수치는 세 세션의 합이어야 한다 — 세션 하나만 쓰면 보호자가 보는
   * 그리기 시간이 실제 활동의 3분의 1로 줄어든다.
   *
   * <p>합치는 규칙은 값의 성격에 따라 다르다. 시간·횟수는 <b>더하고</b>, {@code pressureAvailable}·{@code truncated}는
   * <b>OR</b>다. 한 세션이라도 절단됐으면 합계 전체가 부분 집계이고, 한 세션에서라도 필압이 저장돼 있으면 필압 데이터는 존재한다.
   *
   * <p>배치가 하나도 없는 세션은 조용히 건너뛴다. 모든 세션이 비면 빈 값을 돌려주고, 호출부는 수치를 {@code null}로 남긴다 — 측정하지 못한 값을 0으로
   * 채우면 "한 번도 멈추지 않았다"는 관찰로 읽힌다.
   *
   * @param drawingSessionIds 합칠 그림 활동 세션 식별자 목록이며 {@code null}·빈 목록이면 빈 값
   * @return 합산된 행동 요약, 집계할 배치가 하나도 없으면 빈 값
   */
  public Optional<StrokeBehaviorSummary> summarizeAll(List<Long> drawingSessionIds) {
    if (drawingSessionIds == null || drawingSessionIds.isEmpty()) {
      return Optional.empty();
    }

    List<StrokeBehaviorSummary> summaries =
        drawingSessionIds.stream()
            .filter(Objects::nonNull)
            .distinct()
            .map(this::summarize)
            .flatMap(Optional::stream)
            .toList();
    if (summaries.isEmpty()) {
      return Optional.empty();
    }
    if (summaries.size() == 1) {
      return Optional.of(summaries.get(0));
    }

    long drawingDurationMs = 0;
    long activeDrawingMs = 0;
    int pauseCount = 0;
    int undoCount = 0;
    int eraseCount = 0;
    int toolChangeCount = 0;
    int colorChangeCount = 0;
    boolean pressureAvailable = false;
    boolean truncated = false;
    for (StrokeBehaviorSummary summary : summaries) {
      drawingDurationMs += summary.drawingDurationMs() == null ? 0 : summary.drawingDurationMs();
      activeDrawingMs += summary.activeDrawingMs() == null ? 0 : summary.activeDrawingMs();
      pauseCount += summary.pauseCount() == null ? 0 : summary.pauseCount();
      undoCount += summary.undoCount() == null ? 0 : summary.undoCount();
      eraseCount += summary.eraseCount() == null ? 0 : summary.eraseCount();
      toolChangeCount += summary.toolChangeCount() == null ? 0 : summary.toolChangeCount();
      colorChangeCount += summary.colorChangeCount() == null ? 0 : summary.colorChangeCount();
      pressureAvailable |= summary.pressureAvailable();
      truncated |= summary.truncated();
    }
    return Optional.of(
        new StrokeBehaviorSummary(
            drawingDurationMs,
            activeDrawingMs,
            pauseCount,
            undoCount,
            eraseCount,
            toolChangeCount,
            colorChangeCount,
            pressureAvailable,
            truncated));
  }

  /**
   * 배치 목록에서 행동 요약을 계산한다.
   *
   * @param batches 한 세션의 Stroke 배치 목록
   * @param truncated 배치 수 상한에 걸려 앞부분만 넘어왔는지 여부
   * @return 집계 결과, 유효한 배치가 없으면 빈 값
   */
  static Optional<StrokeBehaviorSummary> aggregate(
      List<StrokeBatchDocument> batches, boolean truncated) {
    List<StrokeBatchDocument> ordered = orderedBatches(batches);
    if (ordered.isEmpty()) {
      return Optional.empty();
    }

    long activeDrawingMs = 0;
    int pauseCount = 0;
    int undoCount = 0;
    int eraseCount = 0;
    int toolChangeCount = 0;
    int colorChangeCount = 0;
    boolean pressureAvailable = false;
    String previousTool = null;
    String previousColor = null;
    Instant previousCreatedAt = null;

    for (StrokeBatchDocument batch : ordered) {
      long batchActiveMs = 0;
      for (StrokeEventDocument event : orderedEvents(batch)) {
        if (!pressureAvailable && hasPressure(event)) {
          pressureAvailable = true;
        }
        String eventType = event.eventType();
        if (UNDO_EVENT_TYPE.equals(eventType)) {
          // REDO는 빼지 않는다. undoCount는 "되돌린 횟수"라는 행동 관찰값이고, 다시 실행은 그것을 지우는 것이 아니라
          //   또 한 번의 마음 바뀜이다. 계약에 redoCount 자리가 없다고 해서 상계하면 망설임의 흔적이 사라진다.
          undoCount++;
          continue;
        }
        if (ERASE_EVENT_TYPE.equals(eventType)) {
          eraseCount++;
          continue;
        }
        if (!STROKE_EVENT_TYPE.equals(eventType)) {
          continue;
        }
        batchActiveMs += strokeDurationMs(event);
        String tool = event.tool();
        if (tool != null) {
          if (previousTool != null && !previousTool.equals(tool)) {
            toolChangeCount++;
          }
          previousTool = tool;
          if (ERASER_TOOL.equals(tool)) {
            eraseCount++;
          }
        }
        String color = event.color();
        if (color != null) {
          // 지우개 획은 색을 싣지 않는다. null을 색 변경으로 세면 PEN→ERASER→PEN이 도구 변경 2회에 더해
          //   색 변경 2회로도 잡혀 같은 행동이 두 번 계산된다. 색을 고른 획끼리만 비교한다.
          // 대소문자를 무시하는 이유: 계약의 색 정규식이 소문자 hex도 허용해서(StrokeEventRequest)
          //   #ff0000과 #FF0000이 섞여 들어오면 같은 색이 변경으로 잡힌다.
          if (previousColor != null && !previousColor.equalsIgnoreCase(color)) {
            colorChangeCount++;
          }
          previousColor = color;
        }
      }
      activeDrawingMs += batchActiveMs;
      Instant createdAt = batch.clientCreatedAt();
      if (previousCreatedAt != null
          && createdAt != null
          && isPause(previousCreatedAt, createdAt, batchActiveMs)) {
        pauseCount++;
      }
      if (createdAt != null) {
        previousCreatedAt = createdAt;
      }
    }

    return Optional.of(
        new StrokeBehaviorSummary(
            drawingDurationMs(ordered, activeDrawingMs),
            activeDrawingMs,
            pauseCount,
            undoCount,
            eraseCount,
            toolChangeCount,
            colorChangeCount,
            pressureAvailable,
            truncated));
  }

  /**
   * 두 배치 사이에서 입력이 없던 시간이 멈춤 기준을 넘는지 판정한다.
   *
   * <p>배치 간 시간에서 그 배치가 실제로 그린 시간을 빼면 남는 것이 유휴 시간이다. 이 값이 실제 멈춤과 어긋나는 세 방향은 이 클래스 javadoc에 적었다.
   */
  private static boolean isPause(Instant previousCreatedAt, Instant createdAt, long batchActiveMs) {
    long idleMs = Duration.between(previousCreatedAt, createdAt).toMillis() - batchActiveMs;
    return idleMs >= PAUSE_THRESHOLD_MS;
  }

  /**
   * 이어진 배치 간격만 더해 전체 그림 시간을 잡는다.
   *
   * <p>첫 배치와 마지막 배치의 시각 차를 그대로 쓰지 않는 이유는 그 사이에 <b>활동 중단</b>이 들어갈 수 있어서다. FE가 앱 백그라운드 전환·모달 진입 때 배치를
   * flush하므로 아이가 앱을 닫았다가 다음 날 이어 그리면 하루가 통째로 들어간다. 그래서 간격을 하나씩 보며 {@link #MAX_CONTINUOUS_GAP_MS}를
   * 넘는 것은 "그리기가 이어지지 않은 구간"으로 보고 더하지 않는다.
   *
   * <p>실제 입력 시간을 하한으로 두는 것은 <b>자기모순 방지</b>다. 그린 시간이 전체 시간보다 길다는 값은 그 자체로 앞뒤가 맞지 않는다. 첫 배치가 만들어지기 전에
   * 그린 시간(최대 flush 주기만큼)이 관측 범위 밖이라 간격 합이 실제보다 짧게 나오고, 배치가 하나뿐이면 간격이 0이 되기 때문에 이 하한이 필요하다. AI는 두 값을
   * 그대로 {@code behaviorFeatures}에 옮겨 적을 뿐 비율을 계산하지는 않는다.
   *
   * <p>배치가 하나뿐인 짧은 활동에서는 이 값이 {@code activeDrawingMs}와 같아진다.
   */
  private static long drawingDurationMs(List<StrokeBatchDocument> ordered, long activeDrawingMs) {
    long spanMs = 0;
    Instant previousCreatedAt = null;
    for (StrokeBatchDocument batch : ordered) {
      Instant createdAt = batch.clientCreatedAt();
      if (createdAt == null) {
        continue;
      }
      if (previousCreatedAt != null) {
        long gapMs = Duration.between(previousCreatedAt, createdAt).toMillis();
        if (gapMs > 0 && gapMs <= MAX_CONTINUOUS_GAP_MS) {
          spanMs += gapMs;
        }
      }
      previousCreatedAt = createdAt;
    }
    return Math.max(spanMs, activeDrawingMs);
  }

  /** 획 하나가 실제로 그려진 시간이다. 좌표 시간은 획 시작 기준이라 첫 좌표와 마지막 좌표의 차가 곧 입력 시간이다. */
  private static long strokeDurationMs(StrokeEventDocument event) {
    List<StrokePointDocument> points = event.points();
    if (points == null || points.isEmpty()) {
      return 0;
    }
    return Math.max(0, points.getLast().elapsedMs() - points.getFirst().elapsedMs());
  }

  /**
   * 이벤트에 필압 값이 실제로 들어 있는지 확인한다.
   *
   * <p>좌표 하나라도 값이 있으면 사용 가능으로 본다. 필압 지원은 입력 기기의 성질이라 지원하는 기기는 모든 좌표에 값을 싣고 아닌 기기는 하나도 싣지 않는다.
   * {@code 0.0}은 "필압 없음"이 아니라 아주 약하게 눌렀다는 측정값이므로 사용 가능으로 센다.
   */
  private static boolean hasPressure(StrokeEventDocument event) {
    if (event.pressure() != null) {
      return true;
    }
    List<StrokePointDocument> points = event.points();
    if (points == null) {
      return false;
    }
    for (StrokePointDocument point : points) {
      if (point != null && point.pressure() != null) {
        return true;
      }
    }
    return false;
  }

  private static List<StrokeBatchDocument> orderedBatches(List<StrokeBatchDocument> batches) {
    if (batches == null || batches.isEmpty()) {
      return List.of();
    }
    return batches.stream()
        .filter(Objects::nonNull)
        .sorted(Comparator.comparingInt(StrokeBatchDocument::batchSeq))
        .toList();
  }

  private static List<StrokeEventDocument> orderedEvents(StrokeBatchDocument batch) {
    List<StrokeEventDocument> strokes = batch.strokes();
    if (strokes == null || strokes.isEmpty()) {
      return List.of();
    }
    return strokes.stream()
        .filter(Objects::nonNull)
        .sorted(Comparator.comparingLong(StrokeEventDocument::strokeSeq))
        .toList();
  }
}
