import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _assessmentId = 91;

final _validPng = Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  8,
  215,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  137,
  153,
  61,
  29,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

void main() {
  testWidgets('exact assessment에서 HOUSE→TREE→PERSON 순서와 상대 인증 URL을 사용한다', (
    tester,
  ) async {
    final repository = _ActivityHistoryRepository(
      pages: {
        0: _page([
          _htpActivity(assessmentId: 12),
          _htpActivity(assessmentId: _assessmentId),
        ]),
      },
    );

    await _pumpEmotion(tester, repository: repository);
    await _pumpImages(tester);

    expect(repository.requestedPages, [0]);
    expect(repository.downloadedUrls, [
      '/api/v1/drawing-assets/house/file',
      '/api/v1/drawing-assets/tree/file',
      '/api/v1/drawing-assets/person/file',
    ]);
    expect(_previewSubjectsInOrder(tester), ['HOUSE', 'TREE', 'PERSON']);
    expect(find.bySemanticsLabel('집 그림 주제'), findsOneWidget);
    expect(find.bySemanticsLabel('나무 그림 주제'), findsOneWidget);
    expect(find.bySemanticsLabel('사람 그림 주제'), findsOneWidget);
    expect(find.text('완성한 그림을 불러오지 못했어요.'), findsNothing);

    for (final subject in const ['HOUSE', 'TREE', 'PERSON']) {
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(ValueKey('htp-emotion-image-$subject')),
          matching: find.byType(Image),
        ),
      );
      expect(image.fit, BoxFit.contain);
    }
  });

  testWidgets('대상이 다음 페이지에 있으면 찾은 페이지에서 조회를 중단한다', (tester) async {
    final repository = _ActivityHistoryRepository(
      pages: {
        0: _page(
          [_htpActivity(assessmentId: 12)],
          page: 0,
          totalPages: 3,
          hasNext: true,
        ),
        1: _page(
          [_htpActivity(assessmentId: _assessmentId)],
          page: 1,
          totalPages: 3,
          hasNext: true,
        ),
        2: _page([_htpActivity(assessmentId: 99)], page: 2, totalPages: 3),
      },
    );

    await _pumpEmotion(tester, repository: repository);
    await _pumpImages(tester);

    expect(repository.requestedPages, [0, 1]);
    expect(repository.downloadedUrls, hasLength(3));
  });

  testWidgets('중복 subject는 첫 장만 쓰고 누락·unknown·malformed URL은 개별 fallback한다', (
    tester,
  ) async {
    final repository = _ActivityHistoryRepository(
      pages: {
        0: _page([
          _htpActivity(
            assessmentId: _assessmentId,
            drawings: const [
              HtpActivityDrawingDto(
                drawingSubject: 'HOUSE',
                drawingSessionId: 1,
                thumbnailUrl: '/api/v1/first-house',
              ),
              HtpActivityDrawingDto(
                drawingSubject: 'HOUSE',
                drawingSessionId: 2,
                thumbnailUrl: '/api/v1/duplicate-house',
              ),
              HtpActivityDrawingDto(
                drawingSubject: 'ALIEN',
                drawingSessionId: 3,
                thumbnailUrl: '/api/v1/unknown',
              ),
              HtpActivityDrawingDto(
                drawingSubject: 'PERSON',
                drawingSessionId: 4,
                thumbnailUrl: 'https://outside.example/person',
              ),
            ],
          ),
        ]),
      },
    );

    await _pumpEmotion(tester, repository: repository);
    await _pumpImages(tester);

    expect(repository.downloadedUrls, ['/api/v1/first-house']);
    expect(find.text('나무 그림을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('사람 그림을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('ALIEN'), findsNothing);
  });

  testWidgets('HOUSE 요청 실패와 TREE decode 실패가 PERSON 성공을 숨기지 않는다', (
    tester,
  ) async {
    final repository = _ActivityHistoryRepository(
      pages: {
        0: _page([_htpActivity(assessmentId: _assessmentId)]),
      },
      imageResults: {
        '/api/v1/drawing-assets/house/file': StateError('404'),
        '/api/v1/drawing-assets/tree/file': Uint8List.fromList([1, 2, 3]),
      },
    );

    await _pumpEmotion(tester, repository: repository);
    await _pumpImages(tester);

    expect(find.text('집 그림을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('나무 그림을 불러오지 못했어요.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('htp-emotion-image-PERSON')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('활동기록 조회 중에는 세 주제 loading placeholder를 안정적으로 표시한다', (
    tester,
  ) async {
    final result = Completer<ApiPage<ActivitySummaryDto>>();
    final repository = _ActivityHistoryRepository(
      activityLoaders: {3: () => result.future},
    );

    await _pumpEmotion(tester, repository: repository, settle: false);
    await tester.pump();

    expect(find.bySemanticsLabel('집 그림 불러오는 중'), findsOneWidget);
    expect(find.bySemanticsLabel('나무 그림 불러오는 중'), findsOneWidget);
    expect(find.bySemanticsLabel('사람 그림 불러오는 중'), findsOneWidget);
    result.complete(_page([_htpActivity(assessmentId: _assessmentId)]));
    await _pumpImages(tester);
    expect(repository.downloadedUrls, hasLength(3));
  });

  testWidgets('세 이미지가 모두 실패해도 세 fallback과 감정 선택을 유지한다', (tester) async {
    final repository = _ActivityHistoryRepository(
      pages: {
        0: _page([_htpActivity(assessmentId: _assessmentId)]),
      },
      imageResults: {
        '/api/v1/drawing-assets/house/file': StateError('401'),
        '/api/v1/drawing-assets/tree/file': StateError('404'),
        '/api/v1/drawing-assets/person/file': StateError('500'),
      },
    );

    await _pumpEmotion(tester, repository: repository);
    await _pumpImages(tester);

    expect(find.text('집 그림을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('나무 그림을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('사람 그림을 불러오지 못했어요.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('emotion-기쁨')),
      300,
      scrollable: _screenScroll(),
    );
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('emotion-confirmation-panel')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('assessment 미발견과 history 실패도 감정 선택·skip을 막지 않는다', (tester) async {
    for (final repository in [
      _ActivityHistoryRepository(
        pages: {
          0: _page([_htpActivity(assessmentId: 12)]),
        },
      ),
      _ActivityHistoryRepository(historyFailure: StateError('500')),
    ]) {
      await _pumpEmotion(tester, repository: repository);

      expect(find.text('집 그림을 불러오지 못했어요.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('emotion-기쁨')),
        300,
        scrollable: _screenScroll(),
      );
      await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('emotion-confirmation-panel')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('emotion-skip')),
        300,
        scrollable: _screenScroll(),
      );
      await tester.tap(find.byKey(const ValueKey('emotion-skip')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('emotion-skip-confirm')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('emotion-skip-cancel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('동일 identity rebuild는 활동기록을 중복 조회하지 않는다', (tester) async {
    final repository = _ActivityHistoryRepository(
      pages: {
        0: _page([_htpActivity(assessmentId: _assessmentId)]),
      },
    );

    await _pumpEmotion(tester, repository: repository);
    await _pumpEmotion(tester, repository: repository, resetView: false);
    await _pumpImages(tester);

    expect(repository.requestedPages, [0]);
  });

  testWidgets('늦은 이전 assessment 응답은 최신 child·assessment gallery를 덮지 않는다', (
    tester,
  ) async {
    final oldResult = Completer<ApiPage<ActivitySummaryDto>>();
    final newResult = Completer<ApiPage<ActivitySummaryDto>>();
    final repository = _ActivityHistoryRepository(
      activityLoaders: {3: () => oldResult.future, 4: () => newResult.future},
    );

    await _pumpEmotion(
      tester,
      repository: repository,
      childId: '3',
      assessmentId: 91,
      settle: false,
    );
    await tester.pump();
    await _pumpEmotion(
      tester,
      repository: repository,
      childId: '4',
      assessmentId: 92,
      resetView: false,
      settle: false,
    );
    await tester.pump();

    newResult.complete(
      _page([_htpActivity(assessmentId: 92, urlPrefix: 'new')]),
    );
    await _pumpImages(tester);
    oldResult.complete(
      _page([_htpActivity(assessmentId: 91, urlPrefix: 'old')]),
    );
    await _pumpImages(tester);

    expect(repository.downloadedUrls, contains('/api/v1/new-house'));
    expect(repository.downloadedUrls, isNot(contains('/api/v1/old-house')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose 후 늦은 history 응답은 상태를 변경하지 않는다', (tester) async {
    final result = Completer<ApiPage<ActivitySummaryDto>>();
    final repository = _ActivityHistoryRepository(
      activityLoaders: {3: () => result.future},
    );
    await _pumpEmotion(tester, repository: repository, settle: false);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    result.complete(_page([_htpActivity(assessmentId: _assessmentId)]));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  for (final viewport in const [
    (name: '320x640 textScale 2.0', size: Size(320, 640), scale: 2.0),
    (name: 'Pixel Tablet 가로', size: Size(1280, 800), scale: 1.0),
    (name: '태블릿 세로', size: Size(800, 1280), scale: 1.0),
  ]) {
    testWidgets('${viewport.name}에서 3장과 emotion·skip이 overflow 없이 접근 가능하다', (
      tester,
    ) async {
      final repository = _ActivityHistoryRepository(
        pages: {
          0: _page([_htpActivity(assessmentId: _assessmentId)]),
        },
      );
      await _pumpEmotion(
        tester,
        repository: repository,
        size: viewport.size,
        textScale: viewport.scale,
      );
      await _pumpImages(tester);
      expect(tester.takeException(), isNull, reason: 'initial gallery');

      expect(_previewSubjectsInOrder(tester), ['HOUSE', 'TREE', 'PERSON']);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('emotion-기쁨')),
        300,
        scrollable: _screenScroll(),
      );
      await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'emotion confirmation');
      expect(
        find.byKey(const ValueKey('emotion-confirmation-panel')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('emotion-skip')),
        300,
        scrollable: _screenScroll(),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('emotion-skip'))).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byKey(const ValueKey('emotion-skip')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'skip confirmation');
      expect(
        find.byKey(const ValueKey('emotion-skip-confirm')),
        findsOneWidget,
      );
    });
  }
}

Finder _screenScroll() => find
    .descendant(
      of: find.byKey(const ValueKey('emotion-screen-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

List<String> _previewSubjectsInOrder(WidgetTester tester) => [
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'htp-emotion-preview-',
                ) &&
                !(widget.key! as ValueKey<String>).value.startsWith(
                  'htp-emotion-preview-label-',
                ) &&
                (widget.key! as ValueKey<String>).value !=
                    'htp-emotion-preview-gallery',
          )
          .evaluate())
    ((element.widget.key! as ValueKey<String>).value.split('-').last),
];

Future<void> _pumpEmotion(
  WidgetTester tester, {
  required ActivityRepository repository,
  String childId = '3',
  int assessmentId = _assessmentId,
  Size size = const Size(1200, 900),
  double textScale = 1,
  bool resetView = true,
  bool settle = true,
}) async {
  if (resetView) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: EmotionSelectScreen(
        key: const ValueKey('emotion-screen'),
        childId: childId,
        activityRepository: repository,
        activityContext: DrawingActivityContextDto(
          activityKind: 'HTP',
          htpAssessmentId: assessmentId,
          htpStatus: 'IN_PROGRESS',
          stepOrder: 3,
          drawingSubject: 'PERSON',
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _pumpImages(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

ApiPage<ActivitySummaryDto> _page(
  List<ActivitySummaryDto> content, {
  int page = 0,
  int totalPages = 1,
  bool hasNext = false,
}) => ApiPage(
  content: content,
  page: page,
  size: 20,
  totalElements: content.length,
  totalPages: totalPages,
  hasNext: hasNext,
);

ActivitySummaryDto _htpActivity({
  required int assessmentId,
  String urlPrefix = 'drawing-assets',
  List<HtpActivityDrawingDto>? drawings,
}) => ActivitySummaryDto(
  activityId: assessmentId * 10,
  title: 'HTP',
  drawingType: const ActivityDrawingTypeDto(code: 'HTP', name: 'HTP'),
  inputMethod: 'UPLOAD',
  sessionStatus: 'COMPLETED',
  selectedEmotions: const [],
  thumbnailUrl: null,
  analysisStatus: null,
  report: null,
  startedAt: '2026-08-03T00:00:00Z',
  completedAt: null,
  activityKind: 'HTP',
  htpAssessmentId: assessmentId,
  htpStatus: 'IN_PROGRESS',
  htpDrawings:
      drawings ??
      [
        for (final subject in const ['HOUSE', 'TREE', 'PERSON'])
          HtpActivityDrawingDto(
            drawingSubject: subject,
            drawingSessionId: subject.hashCode,
            thumbnailUrl: urlPrefix == 'drawing-assets'
                ? '/api/v1/drawing-assets/${subject.toLowerCase()}/file'
                : '/api/v1/$urlPrefix-${subject.toLowerCase()}',
          ),
      ],
);

final class _ActivityHistoryRepository implements ActivityRepository {
  _ActivityHistoryRepository({
    this.pages = const {},
    this.imageResults = const {},
    this.activityLoaders = const {},
    this.historyFailure,
  });

  final Map<int, ApiPage<ActivitySummaryDto>> pages;
  final Map<String, Object> imageResults;
  final Map<int, Future<ApiPage<ActivitySummaryDto>> Function()>
  activityLoaders;
  final Object? historyFailure;
  final List<int> requestedPages = [];
  final List<String> downloadedUrls = [];

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async {
    requestedPages.add(filter.page);
    if (historyFailure case final failure?) throw failure;
    final loader = activityLoaders[childId];
    if (loader != null) return loader();
    return pages[filter.page] ?? _page(const []);
  }

  @override
  Future<Uint8List> downloadImage(String url) async {
    downloadedUrls.add(url);
    final result = imageResults[url];
    if (result is Uint8List) return result;
    if (result != null) throw result;
    return _validPng;
  }

  @override
  Future<void> deleteActivity(int activityId) => throw UnimplementedError();

  @override
  Future<ActivityDetailDto> getActivity(int activityId) =>
      throw UnimplementedError();

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) => throw UnimplementedError();
}
