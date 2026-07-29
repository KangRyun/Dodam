import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('실제 activityId로 상세를 조회하고 DTO 필드를 표시한다', (tester) async {
    final repository = _DetailRepository();
    await _openDetail(tester, repository);

    expect(repository.detailCalls, [120]);
    expect(repository.messageCalls, [77]);
    expect(find.text('우리 가족'), findsOneWidget);
    expect(find.text('그림일기'), findsWidgets);
    expect(find.text('기쁨'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-detail-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-report-cta')), findsOneWidget);
  });

  testWidgets('AI 질문 원문과 선택형 답변을 연결해 표시한다', (tester) async {
    await _openDetail(tester, _DetailRepository());

    expect(
      find.byKey(const ValueKey('activity-detail-conversation-turns')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('conversation-turn-801')), findsOneWidget);
    expect(find.text('이 그림에서 가장 마음에 드는 곳은 어디야?'), findsOneWidget);
    // 질문 선택지
    expect(find.text('🏠 집'), findsOneWidget);
    expect(find.text('🙂 사람'), findsOneWidget);
    // 선택형 답변 라벨 + 직접 입력 문장
    expect(find.textContaining('집'), findsWidgets);
    expect(find.textContaining('우리 집 지붕이 제일 좋아'), findsOneWidget);
    // 질문과 답변이 같은 묶음 안에 있다.
    final turn = find.byKey(const ValueKey('conversation-turn-801'));
    expect(
      find.descendant(
        of: turn,
        matching: find.textContaining('우리 집 지붕이 제일 좋아'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('음성 답변의 STT 결과를 질문과 연결해 표시한다', (tester) async {
    await _openDetail(tester, _DetailRepository());

    final turn = find.byKey(const ValueKey('conversation-turn-803'));
    expect(
      find.descendant(of: turn, matching: find.text('집 앞에 있는 사람은 누구야?')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: turn, matching: find.text('엄마랑 동생이야')),
      findsOneWidget,
    );
  });

  testWidgets('STT 처리 중·실패 상태를 안내한다', (tester) async {
    await _openDetail(tester, _DetailRepository());

    expect(find.text('목소리를 글로 바꾸고 있어요.'), findsOneWidget);
    expect(find.text('목소리를 글로 바꾸지 못했어요. 녹음한 답변은 안전하게 보관했어요.'), findsOneWidget);
  });

  testWidgets('Skip된 질문과 답변 없는 질문을 구분해 표시한다', (tester) async {
    await _openDetail(tester, _DetailRepository());

    final skipped = find.byKey(const ValueKey('conversation-turn-807'));
    expect(
      find.descendant(of: skipped, matching: find.text('건너뛴 질문')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: skipped, matching: find.text('이 질문은 건너뛰었어요.')),
      findsOneWidget,
    );

    final unanswered = find.byKey(const ValueKey('conversation-turn-811'));
    expect(
      find.descendant(of: unanswered, matching: find.text('아직 답변이 없어요.')),
      findsOneWidget,
    );
  });

  testWidgets('여러 질문을 sequence 오름차순으로 세운다', (tester) async {
    // Repository가 sequence 뒤섞인 순서로 줘도 화면은 순번대로 세운다.
    await _openDetail(tester, _DetailRepository());

    final offsets = [
      for (final messageId in [801, 803, 805, 807, 811, 813])
        tester
            .getTopLeft(find.byKey(ValueKey('conversation-turn-$messageId')))
            .dy,
    ];

    expect(offsets, orderedEquals(List.of(offsets)..sort()));
    expect(offsets.toSet(), hasLength(offsets.length));
  });

  testWidgets('알 수 없는 메시지 유형이 섞여도 대화 전체가 실패하지 않는다', (tester) async {
    final repository = _DetailRepository(
      messages: const [
        ActivityConversationMessageDto(
          messageId: 901,
          sequence: 1,
          senderType: 'AI',
          messageType: 'QUESTION',
          rawText: '무엇을 그렸어?',
        ),
        ActivityConversationMessageDto(
          messageId: 902,
          sequence: 2,
          senderType: 'CHILD',
          messageType: 'FUTURE_UNKNOWN_TYPE',
          parentMessageId: 901,
          rawText: '알 수 없는 유형이지만 내용은 있어',
        ),
      ],
    );
    await _openDetail(tester, repository);

    expect(tester.takeException(), isNull);
    expect(find.text('무엇을 그렸어?'), findsOneWidget);
    expect(find.text('알 수 없는 유형이지만 내용은 있어'), findsNothing);
    expect(find.text('아직 답변이 없어요.'), findsOneWidget);
  });

  testWidgets('SYSTEM과 비아동 ANSWER 메시지는 아이 답변으로 표시하지 않는다', (tester) async {
    final repository = _DetailRepository(
      messages: const [
        ActivityConversationMessageDto(
          messageId: 901,
          sequence: 1,
          senderType: 'AI',
          messageType: 'QUESTION',
          rawText: '무엇을 그렸어?',
        ),
        ActivityConversationMessageDto(
          messageId: 902,
          sequence: 2,
          senderType: 'SYSTEM',
          messageType: 'SYSTEM',
          parentMessageId: 901,
          rawText: '시스템 알림',
        ),
        ActivityConversationMessageDto(
          messageId: 903,
          sequence: 3,
          senderType: 'AI',
          messageType: 'ANSWER_TEXT',
          parentMessageId: 901,
          rawText: '비아동 답변',
        ),
      ],
    );
    await _openDetail(tester, repository);

    expect(find.text('무엇을 그렸어?'), findsOneWidget);
    expect(find.text('시스템 알림'), findsNothing);
    expect(find.text('비아동 답변'), findsNothing);
    expect(find.text('아직 답변이 없어요.'), findsOneWidget);
  });

  testWidgets('CHILD ANSWER_TEXT를 질문의 아이 답변으로 표시한다', (tester) async {
    final repository = _DetailRepository(
      messages: const [
        ActivityConversationMessageDto(
          messageId: 901,
          sequence: 1,
          senderType: 'AI',
          messageType: 'QUESTION',
          rawText: '무엇을 그렸어?',
        ),
        ActivityConversationMessageDto(
          messageId: 902,
          sequence: 2,
          senderType: 'CHILD',
          messageType: 'ANSWER_TEXT',
          parentMessageId: 901,
          rawText: '우리 가족을 그렸어',
        ),
      ],
    );
    await _openDetail(tester, repository);

    final turn = find.byKey(const ValueKey('conversation-turn-901'));
    expect(
      find.descendant(of: turn, matching: find.text('우리 가족을 그렸어')),
      findsOneWidget,
    );
  });

  testWidgets('복수 고아 CHILD 답변에 서로 다른 안정적인 Key를 사용한다', (tester) async {
    final repository = _DetailRepository(
      messages: const [
        ActivityConversationMessageDto(
          messageId: 901,
          sequence: 4,
          senderType: 'CHILD',
          messageType: 'ANSWER_TEXT',
          parentMessageId: 800,
          rawText: '첫 번째 고아 답변',
        ),
        ActivityConversationMessageDto(
          messageId: 902,
          sequence: 2,
          senderType: 'CHILD',
          messageType: 'ANSWER_VOICE',
          parentMessageId: 801,
          sttText: '두 번째 고아 답변',
          speechStatus: 'SUCCESS',
        ),
      ],
    );
    await _openDetail(tester, repository);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('conversation-turn-orphan-901')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('conversation-turn-orphan-902')),
      findsOneWidget,
    );
  });

  testWidgets('중복 messageId는 중복 표시하지 않는다', (tester) async {
    final repository = _DetailRepository(
      messages: const [
        ActivityConversationMessageDto(
          messageId: 901,
          sequence: 1,
          senderType: 'AI',
          messageType: 'QUESTION',
          rawText: '무엇을 그렸어?',
        ),
        ActivityConversationMessageDto(
          messageId: 901,
          sequence: 1,
          senderType: 'AI',
          messageType: 'QUESTION',
          rawText: '무엇을 그렸어?',
        ),
      ],
    );
    await _openDetail(tester, repository);

    expect(find.text('무엇을 그렸어?'), findsOneWidget);
  });

  testWidgets('대화 조회 중 대화 영역에 Loading을 표시한다', (tester) async {
    final pending = Completer<List<ActivityConversationMessageDto>>();
    final repository = _DetailRepository(pendingMessages: pending);
    await _openDetail(tester, repository, settle: false);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('activity-detail-conversation-loading')),
      findsOneWidget,
    );
    pending.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('빈 대화는 정상적인 Empty 상태로 표시한다', (tester) async {
    await _openDetail(tester, _DetailRepository(messages: const []));

    expect(
      find.byKey(const ValueKey('activity-detail-conversation-empty')),
      findsOneWidget,
    );
    expect(find.text('아직 주고받은 대화가 없어요'), findsOneWidget);
  });

  testWidgets('conversationId가 없으면 메시지 API를 부르지 않는다', (tester) async {
    final repository = _DetailRepository(
      detail: _detailWith(conversationId: null),
    );
    await _openDetail(tester, repository);

    expect(repository.messageCalls, isEmpty);
    expect(
      find.byKey(const ValueKey('activity-detail-conversation-none')),
      findsOneWidget,
    );
    expect(find.text('이 활동에서 제공된 대화 정보가 없어요.'), findsOneWidget);
  });

  testWidgets('대화 조회 실패는 활동 상세를 가리지 않고 그 영역만 재시도한다', (tester) async {
    final repository = _DetailRepository(messageError: StateError('network'));
    await _openDetail(tester, repository);

    // 대화 영역만 오류다.
    expect(
      find.byKey(const ValueKey('activity-detail-conversation-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('activity-detail-error')), findsNothing);
    // 그림과 활동 기본 정보는 그대로 남는다.
    expect(find.byKey(const ValueKey('activity-detail-image')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activity-detail-basic-info')),
      findsOneWidget,
    );
    expect(find.text('우리 가족'), findsOneWidget);

    repository.messageError = null;
    await tester.ensureVisible(find.text('다시 시도'));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    // 활동 상세는 다시 부르지 않고 대화만 다시 부른다.
    expect(repository.detailCalls, [120]);
    expect(repository.messageCalls, [77, 77]);
    expect(find.text('이 그림에서 가장 마음에 드는 곳은 어디야?'), findsOneWidget);
  });

  testWidgets('상세 조회 중 Loading을 표시한다', (tester) async {
    final pending = Completer<ActivityDetailDto>();
    final repository = _DetailRepository(pending: pending);
    await _openDetail(tester, repository, settle: false);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('activity-detail-loading')),
      findsOneWidget,
    );
    pending.complete(_detail);
    await tester.pumpAndSettle();
  });

  testWidgets('조회 실패 후 Retry할 수 있다', (tester) async {
    final repository = _DetailRepository(error: StateError('network'));
    await _openDetail(tester, repository);
    expect(find.byKey(const ValueKey('activity-detail-error')), findsOneWidget);

    repository.error = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(repository.detailCalls, [120, 120]);
    expect(find.text('우리 가족'), findsOneWidget);
  });

  testWidgets('잘못된 activityId는 조회하지 않고 안전하게 안내한다', (tester) async {
    final repository = _DetailRepository();
    await _openDetail(tester, repository, activityId: 'invalid');

    expect(repository.detailCalls, isEmpty);
    expect(repository.messageCalls, isEmpty);
    expect(
      find.byKey(const ValueKey('activity-detail-invalid-id')),
      findsOneWidget,
    );
  });

  testWidgets('응답 ID가 다르면 가짜 상세 대신 Empty를 표시한다', (tester) async {
    final repository = _DetailRepository(detail: _detailWith(activityId: 121));
    await _openDetail(tester, repository);
    expect(find.byKey(const ValueKey('activity-detail-empty')), findsOneWidget);
    expect(repository.messageCalls, isEmpty);
  });

  testWidgets('화면을 벗어난 뒤 늦게 도착한 응답은 안전하게 무시한다', (tester) async {
    final pending = Completer<List<ActivityConversationMessageDto>>();
    final repository = _DetailRepository(pendingMessages: pending);
    await _openDetail(tester, repository, settle: false);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    // 조회가 실제로 진행 중이어야 검증에 의미가 있다.
    expect(repository.messageCalls, [77]);

    // 상세 화면을 완전히 버린 뒤에 응답이 도착한다.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    pending.complete(_messages);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('이미지 실패와 nullable 데이터에도 화면을 유지한다', (tester) async {
    final repository = _DetailRepository(
      detail: _detailWith(
        title: null,
        selectedEmotions: const [],
        latestAsset: null,
        latestAnalysis: null,
        conversationId: null,
        reportId: null,
      ),
    );
    await _openDetail(tester, repository);
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('activity-detail-image-placeholder')),
      findsOneWidget,
    );
    expect(find.text('선택한 감정 정보가 없어요.'), findsOneWidget);
    expect(find.text('이 활동에서 제공된 대화 정보가 없어요.'), findsOneWidget);
    expect(find.text('아직 생성된 요약이 없어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-report-cta')), findsNothing);
  });

  testWidgets('실제 reportId가 있을 때만 Report route로 이동한다', (tester) async {
    await _openDetail(tester, _DetailRepository());
    await tester.ensureVisible(
      find.byKey(const ValueKey('activity-report-cta')),
    );
    await tester.tap(find.byKey(const ValueKey('activity-report-cta')));
    await tester.pumpAndSettle();

    expect(find.text('관찰 리포트'), findsWidgets);
  });

  testWidgets('긴 질문과 긴 답변도 overflow 없이 표시한다', (tester) async {
    final long = '아' * 400;
    final repository = _DetailRepository(
      messages: [
        ActivityConversationMessageDto(
          messageId: 901,
          sequence: 1,
          senderType: 'AI',
          messageType: 'QUESTION',
          rawText: long,
        ),
        ActivityConversationMessageDto(
          messageId: 902,
          sequence: 2,
          senderType: 'CHILD',
          messageType: 'ANSWER_VOICE',
          parentMessageId: 901,
          sttText: long,
          speechStatus: 'SUCCESS',
        ),
      ],
    );
    await _openDetail(tester, repository);

    expect(tester.takeException(), isNull);
    expect(find.text(long), findsNWidgets(2));
  });

  testWidgets('작은 화면은 단일 스크롤로 overflow 없이 표시한다', (tester) async {
    tester.view.physicalSize = const Size(500, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDetail(tester, _DetailRepository());
    expect(
      find.byKey(const ValueKey('activity-detail-small-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('textScale 2.0에서도 대화가 overflow 없이 표시된다', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _openDetail(tester, _DetailRepository());

    expect(tester.takeException(), isNull);
    expect(find.text('이 그림에서 가장 마음에 드는 곳은 어디야?'), findsOneWidget);
  });

  testWidgets('질문과 답변에 접근성 Semantics를 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();

    await _openDetail(tester, _DetailRepository());

    expect(
      find.bySemanticsLabel('AI 질문. 이 그림에서 가장 마음에 드는 곳은 어디야?'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('질문 선택지. 집, 사람'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^아이 답변\\. 엄마랑 동생이야')), findsOneWidget);

    semantics.dispose();
  });
}

Future<void> _openDetail(
  WidgetTester tester,
  ActivityRepository repository, {
  String activityId = '120',
  bool settle = true,
}) async {
  await tester.pumpWidget(
    DodamApp(
      activityRepository: repository,
      initialRoute: AppRoutes.activityDetail(activityId),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final class _DetailRepository implements ActivityRepository {
  _DetailRepository({
    ActivityDetailDto? detail,
    List<ActivityConversationMessageDto>? messages,
    this.pending,
    this.pendingMessages,
    this.error,
    this.messageError,
  }) : detail = detail ?? _detail,
       messages = messages ?? _messages;

  ActivityDetailDto detail;
  List<ActivityConversationMessageDto> messages;
  final Completer<ActivityDetailDto>? pending;
  final Completer<List<ActivityConversationMessageDto>>? pendingMessages;
  Object? error;
  Object? messageError;
  final List<int> detailCalls = [];
  final List<int> messageCalls = [];

  @override
  Future<ActivityDetailDto> getActivity(int activityId) async {
    detailCalls.add(activityId);
    if (error case final error?) throw error;
    return pending?.future ?? detail;
  }

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) async {
    messageCalls.add(conversationId);
    if (messageError case final error?) throw error;
    return pendingMessages?.future ?? messages;
  }

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) => throw UnimplementedError();

  @override
  Future<void> deleteActivity(int activityId) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadImage(String url) =>
      throw StateError('image fetch failed');
}

const _asset = ActivityAssetDto(
  drawingAssetId: 900,
  assetType: 'FINAL',
  assetVersion: 2,
  mimeType: 'image/png',
  widthPx: 1600,
  heightPx: 1000,
);

const _analysis = ActivityAnalysisSummaryDto(
  drawingAnalysisId: 88,
  analysisStatus: 'COMPLETED',
  analysisScope: 'FINAL',
  completedAt: '2026-07-20T10:11:00Z',
);

final _detail = _detailWith();

ActivityDetailDto _detailWith({
  int activityId = 120,
  String? title = '우리 가족',
  List<String> selectedEmotions = const ['HAPPY'],
  ActivityAssetDto? latestAsset = _asset,
  ActivityAnalysisSummaryDto? latestAnalysis = _analysis,
  int? conversationId = 77,
  int? reportId = 501,
}) => ActivityDetailDto(
  activityId: activityId,
  childId: 3,
  childNickname: '도담이',
  title: title,
  drawingType: const ActivityDrawingTypeDto(code: 'ART_DIARY', name: '그림일기'),
  inputMethod: 'CANVAS',
  sessionStatus: 'COMPLETED',
  currentStage: 'COMPLETED',
  selectedEmotions: selectedEmotions,
  startedAt: '2026-07-20T09:40:00Z',
  completedAt: '2026-07-20T10:03:00Z',
  latestAsset: latestAsset,
  latestAnalysis: latestAnalysis,
  conversationId: conversationId,
  reportId: reportId,
);

/// 보호자 상세가 다루어야 하는 답변 형태를 모아둔 대화 —
/// 선택형·직접 입력·음성 STT 성공·변환 중·건너뜀·무답변·변환 실패.
/// 일부러 sequence 오름차순이 아닌 순서로 둬 정렬을 검증한다.
const _messages = <ActivityConversationMessageDto>[
  ActivityConversationMessageDto(
    messageId: 804,
    sequence: 4,
    senderType: 'CHILD',
    messageType: 'ANSWER_VOICE',
    parentMessageId: 803,
    sttText: '엄마랑 동생이야',
    speechStatus: 'SUCCESS',
    sttConfidence: 0.91,
    createdAt: '2026-07-20T09:53:30',
  ),
  ActivityConversationMessageDto(
    messageId: 801,
    sequence: 1,
    senderType: 'AI',
    messageType: 'QUESTION',
    rawText: '이 그림에서 가장 마음에 드는 곳은 어디야?',
    options: [
      ActivityConversationOptionDto(
        optionId: 'HOUSE',
        type: 'OPTION',
        label: '집',
        value: 'HOUSE',
        emoji: '🏠',
      ),
      ActivityConversationOptionDto(
        optionId: 'PERSON',
        type: 'OPTION',
        label: '사람',
        value: 'PERSON',
        emoji: '🙂',
      ),
    ],
    createdAt: '2026-07-20T09:52:00',
  ),
  ActivityConversationMessageDto(
    messageId: 802,
    sequence: 2,
    senderType: 'CHILD',
    messageType: 'ANSWER_OPTION',
    parentMessageId: 801,
    selectedResponse: ActivityConversationSelectedResponseDto(
      selectedOptions: [
        ActivityConversationSelectedOptionDto(
          optionId: 'HOUSE',
          labelSnapshot: '집',
          type: 'STATIC',
          value: 'HOUSE',
        ),
      ],
      directText: '우리 집 지붕이 제일 좋아',
    ),
    createdAt: '2026-07-20T09:52:20',
  ),
  ActivityConversationMessageDto(
    messageId: 803,
    sequence: 3,
    senderType: 'AI',
    messageType: 'QUESTION',
    rawText: '집 앞에 있는 사람은 누구야?',
    createdAt: '2026-07-20T09:53:00',
  ),
  ActivityConversationMessageDto(
    messageId: 805,
    sequence: 5,
    senderType: 'AI',
    messageType: 'QUESTION',
    rawText: '그때 기분은 어땠어?',
    createdAt: '2026-07-20T09:54:00',
  ),
  ActivityConversationMessageDto(
    messageId: 806,
    sequence: 6,
    senderType: 'CHILD',
    messageType: 'ANSWER_VOICE',
    parentMessageId: 805,
    speechStatus: 'PROCESSING',
    createdAt: '2026-07-20T09:54:20',
  ),
  ActivityConversationMessageDto(
    messageId: 807,
    sequence: 7,
    senderType: 'AI',
    messageType: 'QUESTION',
    rawText: '또 그리고 싶은 게 있어?',
    isSkipped: true,
    createdAt: '2026-07-20T09:55:00',
  ),
  ActivityConversationMessageDto(
    messageId: 811,
    sequence: 8,
    senderType: 'AI',
    messageType: 'QUESTION',
    rawText: '오늘 그림을 누구에게 보여주고 싶어?',
    createdAt: '2026-07-20T09:56:00',
  ),
  ActivityConversationMessageDto(
    messageId: 813,
    sequence: 9,
    senderType: 'AI',
    messageType: 'QUESTION',
    rawText: '다음에는 무엇을 그려볼까?',
    createdAt: '2026-07-20T09:57:00',
  ),
  ActivityConversationMessageDto(
    messageId: 814,
    sequence: 10,
    senderType: 'CHILD',
    messageType: 'ANSWER_VOICE',
    parentMessageId: 813,
    speechStatus: 'FAILED',
    createdAt: '2026-07-20T09:57:30',
  ),
];
