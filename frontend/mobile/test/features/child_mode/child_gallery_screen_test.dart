import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child_mode/data/child_home_intro_store.dart';
import 'package:dodam/features/child_mode/presentation/screens/child_gallery_screen.dart';
import 'package:dodam/features/child_mode/presentation/screens/child_mode_screens.dart';
import 'package:dodam/features/drawing/data/repositories/mock_drawing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _child = ChildSummaryDto(
  childId: 7,
  nickname: '도담',
  birthDate: '2020-01-01',
  age: 6,
  profileImageUrl: null,
  preferredCharacter: 'BASE',
  questionDifficulty: 'EASY',
  tutorialStatus: 'DONE',
  relationshipType: 'PARENT',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

const _otherChild = ChildSummaryDto(
  childId: 8,
  nickname: '새봄',
  birthDate: '2019-01-01',
  age: 7,
  profileImageUrl: null,
  preferredCharacter: 'DINO',
  questionDifficulty: 'MEDIUM',
  tutorialStatus: 'DONE',
  relationshipType: 'PARENT',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

ActivitySummaryDto _general(
  int id,
  String title, {
  String? thumbnailUrl,
  String status = 'COMPLETED',
  ActivityReportSummaryDto? report,
}) => ActivitySummaryDto(
  activityId: id,
  title: title,
  drawingType: const ActivityDrawingTypeDto(code: 'ART_DIARY', name: '그림일기'),
  inputMethod: 'TOUCH',
  sessionStatus: status,
  selectedEmotions: const ['JOY'],
  thumbnailUrl: thumbnailUrl ?? '/api/v1/drawing-assets/$id/file',
  analysisStatus: 'COMPLETED',
  report: report,
  startedAt: '2026-07-30T09:00:00Z',
  completedAt: status == 'COMPLETED' ? '2026-07-30T09:20:00Z' : null,
);

ActivitySummaryDto _htp(
  int assessmentId, {
  List<HtpActivityDrawingDto>? drawings,
}) => ActivitySummaryDto(
  activityId: assessmentId * 10 + 3,
  title: 'HTP 분석용 제목',
  drawingType: const ActivityDrawingTypeDto(code: 'HTP', name: '집·나무·사람 그림'),
  inputMethod: 'TOUCH',
  sessionStatus: 'COMPLETED',
  selectedEmotions: const ['SAD'],
  thumbnailUrl: '/api/v1/drawing-assets/${assessmentId * 10 + 3}/file',
  analysisStatus: 'COMPLETED',
  report: const ActivityReportSummaryDto(
    reportId: 991,
    reportStatus: 'COMPLETED',
  ),
  startedAt: '2026-07-29T09:00:00Z',
  completedAt: '2026-07-29T10:00:00Z',
  activityKind: 'HTP',
  htpAssessmentId: assessmentId,
  htpStatus: 'COMPLETED',
  htpDrawings:
      drawings ??
      [
        HtpActivityDrawingDto(
          drawingSubject: 'PERSON',
          drawingSessionId: assessmentId * 10 + 3,
          thumbnailUrl: '/api/v1/drawing-assets/${assessmentId * 10 + 3}/file',
        ),
        HtpActivityDrawingDto(
          drawingSubject: 'HOUSE',
          drawingSessionId: assessmentId * 10 + 1,
          thumbnailUrl: '/api/v1/drawing-assets/${assessmentId * 10 + 1}/file',
        ),
        HtpActivityDrawingDto(
          drawingSubject: 'TREE',
          drawingSessionId: assessmentId * 10 + 2,
          thumbnailUrl: '/api/v1/drawing-assets/${assessmentId * 10 + 2}/file',
        ),
      ],
);

ApiPage<ActivitySummaryDto> _page(
  List<ActivitySummaryDto> content, {
  int page = 0,
  bool hasNext = false,
}) => ApiPage<ActivitySummaryDto>(
  content: content,
  page: page,
  size: 20,
  totalElements: content.length + (hasNext ? 1 : 0),
  totalPages: page + (hasNext ? 2 : 1),
  hasNext: hasNext,
);

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

typedef _PageHandler =
    Future<ApiPage<ActivitySummaryDto>> Function(
      int childId,
      ActivityFilterDto filter,
    );

final class _FakeActivityRepository implements ActivityRepository {
  _FakeActivityRepository({required this._handler});

  final _PageHandler _handler;
  final List<(int, ActivityFilterDto)> requests = [];
  final List<String> downloads = [];
  final Set<String> failingImages = {};
  final Set<String> corruptImages = {};

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) {
    requests.add((childId, filter));
    return _handler(childId, filter);
  }

  @override
  Future<Uint8List> downloadImage(String url) async {
    downloads.add(url);
    if (failingImages.contains(url)) throw StateError('image failed');
    if (corruptImages.contains(url)) return Uint8List.fromList([1, 2, 3]);
    return _png;
  }

  @override
  Future<ActivityDetailDto> getActivity(int activityId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteActivity(int activityId) => throw UnimplementedError();

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) => throw UnimplementedError();
}

final class _SeenIntroStore implements ChildHomeIntroStore {
  @override
  Future<bool> hasSeen(int childId) async => true;

  @override
  Future<void> markSeen(int childId) async {}
}

Widget _gallery(
  _FakeActivityRepository repository, {
  ChildSummaryDto child = _child,
  double textScale = 1,
}) => MaterialApp(
  builder: (context, childWidget) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: childWidget!,
  ),
  home: ChildGalleryScreen(child: child, repository: repository),
);

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
}

void _resetViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

Future<void> _openFirstArtwork(WidgetTester tester, String title) async {
  final artwork = find.bySemanticsLabel('$title 그림 크게 보기');
  await tester.ensureVisible(artwork);
  await tester.pumpAndSettle();
  await tester.tap(artwork);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('아동 홈에서 실제 tap하면 정확한 childId의 gallery route로 진입한다', (
    tester,
  ) async {
    String? openedRoute;
    await tester.pumpWidget(
      MaterialApp(
        home: ChildModeHomeScreen(
          child: _child,
          drawingRepository: const MockDrawingRepository(),
          introStore: _SeenIntroStore(),
        ),
        onGenerateRoute: (settings) {
          openedRoute = settings.name;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('아동 그림 갤러리')),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey('past-drawings-entry'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(openedRoute, AppRoutes.childGallery('7'));
    expect(find.text('아동 그림 갤러리'), findsOneWidget);
  });

  testWidgets('완료된 일반 그림만 서버 제목과 완료 날짜로 표시한다', (tester) async {
    final repository = _FakeActivityRepository(
      handler: (_, _) async => _page([
        _general(1, '우리 가족'),
        _general(2, '진행 중 그림', status: 'IN_PROGRESS'),
      ]),
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();

    expect(find.text('우리 가족'), findsOneWidget);
    expect(find.text('7월 30일'), findsOneWidget);
    expect(find.text('진행 중 그림'), findsNothing);
    expect(repository.requests.single.$2.status, 'COMPLETED');
    expect(repository.requests.single.$2.size, 20);
  });

  testWidgets('HTP는 서버 순서와 무관하게 HOUSE TREE PERSON으로 표시한다', (tester) async {
    _setViewport(tester, const Size(800, 1280));
    addTearDown(() => _resetViewport(tester));
    final repository = _FakeActivityRepository(
      handler: (_, _) async => _page([_htp(5)]),
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();

    final urls = tester
        .widgetList(
          find.byType(
            // AuthenticatedImage는 production widget의 실제 인증 fetcher를 사용한다.
            // dynamic 타입 회피 없이 widget 목록 순서로 서버 URL 전달을 검증한다.
            // ignore: deprecated_member_use
            Image,
          ),
        )
        .toList();
    expect(find.text('집 그림'), findsOneWidget);
    expect(find.text('나무 그림'), findsOneWidget);
    expect(find.text('사람 그림'), findsOneWidget);
    expect(repository.downloads.take(3), [
      '/api/v1/drawing-assets/51/file',
      '/api/v1/drawing-assets/52/file',
      '/api/v1/drawing-assets/53/file',
    ]);
    expect(urls, isNotEmpty);
  });

  testWidgets('unknown HTP subject와 빈 URL은 제외하고 알려진 단계만 유지한다', (tester) async {
    final repository = _FakeActivityRepository(
      handler: (_, _) async => _page([
        _htp(
          6,
          drawings: const [
            HtpActivityDrawingDto(
              drawingSubject: 'ALIEN',
              drawingSessionId: 60,
              thumbnailUrl: '/api/v1/drawing-assets/60/file',
            ),
            HtpActivityDrawingDto(
              drawingSubject: 'HOUSE',
              drawingSessionId: 61,
              thumbnailUrl: '/api/v1/drawing-assets/61/file',
            ),
            HtpActivityDrawingDto(
              drawingSubject: 'TREE',
              drawingSessionId: 62,
              thumbnailUrl: '',
            ),
          ],
        ),
      ]),
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();

    expect(find.text('집 그림'), findsOneWidget);
    expect(find.text('나무 그림'), findsNothing);
    expect(find.text('ALIEN'), findsNothing);
  });

  testWidgets('스크롤 끝에서 다음 페이지를 한 번만 요청하고 loading을 표시한다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    addTearDown(() => _resetViewport(tester));
    final secondPage = Completer<ApiPage<ActivitySummaryDto>>();
    final repository = _FakeActivityRepository(
      handler: (_, filter) {
        if (filter.page == 0) {
          return Future.value(
            _page([
              for (var i = 1; i <= 8; i++) _general(i, '그림 $i'),
            ], hasNext: true),
          );
        }
        return secondPage.future;
      },
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('child-gallery-scroll')),
      const Offset(0, -2200),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('child-gallery-load-more')),
      findsOneWidget,
    );
    expect(
      repository.requests.where((request) => request.$2.page == 1),
      hasLength(1),
    );

    secondPage.complete(_page([_general(9, '다음 페이지 그림')], page: 1));
    await tester.pumpAndSettle();
    expect(find.text('다음 페이지 그림'), findsOneWidget);
  });

  testWidgets('페이지 경계의 동일 drawingSessionId는 한 번만 표시한다', (tester) async {
    final repository = _FakeActivityRepository(
      handler: (_, filter) async => filter.page == 0
          ? _page([_general(1, '중복 원본')], hasNext: true)
          : _page([_general(1, '중복 사본'), _general(2, '새 그림')], page: 1),
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-artwork-1')), findsOneWidget);
    expect(find.text('중복 사본'), findsNothing);
    expect(find.text('새 그림'), findsOneWidget);
  });

  testWidgets('첫 페이지에 그림이 없으면 화면을 채우기 위해 다음 페이지를 조회한다', (tester) async {
    final repository = _FakeActivityRepository(
      handler: (_, filter) async => filter.page == 0
          ? _page([_general(1, '이미지 없음', thumbnailUrl: '')], hasNext: true)
          : _page([_general(2, '찾은 그림')], page: 1),
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();

    expect(find.text('찾은 그림'), findsOneWidget);
    expect(repository.requests.map((request) => request.$2.page), [0, 1]);
  });

  testWidgets('완료 그림이 없으면 아동용 empty 상태에서 홈으로 돌아간다', (tester) async {
    final repository = _FakeActivityRepository(
      handler: (_, _) async => _page([_general(1, '없음', thumbnailUrl: '')]),
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();

    expect(find.text('아직 전시된 그림이 없어요'), findsOneWidget);
    expect(find.text('그림 그리러 가기'), findsOneWidget);
  });

  testWidgets('전체 조회 실패는 재시도 가능한 아동용 오류 상태를 표시한다', (tester) async {
    var fail = true;
    final repository = _FakeActivityRepository(
      handler: (_, _) async {
        if (fail) throw StateError('history failed');
        return _page([_general(1, '복구된 그림')]);
      },
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();
    expect(find.text('전시관을 열지 못했어요'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('복구된 그림'), findsOneWidget);
  });

  testWidgets('한 이미지 다운로드 실패가 다른 그림 렌더링을 막지 않는다', (tester) async {
    final repository = _FakeActivityRepository(
      handler: (_, _) async =>
          _page([_general(1, '실패 그림'), _general(2, '정상 그림')]),
    )..failingImages.add('/api/v1/drawing-assets/1/file');

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('child-artwork-image-fallback')),
      findsWidgets,
    );
    expect(
      find.byKey(const ValueKey('authenticated-image-success')),
      findsOneWidget,
    );
    expect(find.text('정상 그림'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decode 실패도 fallback하고 화면 예외로 번지지 않는다', (tester) async {
    final repository = _FakeActivityRepository(
      handler: (_, _) async => _page([_general(1, '깨진 그림')]),
    )..corruptImages.add('/api/v1/drawing-assets/1/file');

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('child-artwork-image-fallback')),
      findsOneWidget,
    );
    expect(find.text('깨진 그림'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('초기 조회 중 skeleton과 loading semantics를 표시한다', (tester) async {
    final pending = Completer<ApiPage<ActivitySummaryDto>>();
    final repository = _FakeActivityRepository(
      handler: (_, _) => pending.future,
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pump();

    expect(find.byKey(const ValueKey('child-gallery-loading')), findsOneWidget);
    expect(find.bySemanticsLabel('지난 그림 불러오는 중'), findsOneWidget);

    pending.complete(_page([]));
    await tester.pumpAndSettle();
  });

  testWidgets('동일 identity rebuild는 history 요청을 중복 생성하지 않는다', (tester) async {
    final repository = _FakeActivityRepository(
      handler: (_, _) async => _page([_general(1, '한 번만')]),
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_gallery(repository));
    await tester.pump();

    expect(repository.requests, hasLength(1));
  });

  testWidgets('childId 변경 시 이전 아이의 늦은 응답을 폐기한다', (tester) async {
    final oldResponse = Completer<ApiPage<ActivitySummaryDto>>();
    final newResponse = Completer<ApiPage<ActivitySummaryDto>>();
    final repository = _FakeActivityRepository(
      handler: (childId, _) =>
          childId == 7 ? oldResponse.future : newResponse.future,
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pump();
    await tester.pumpWidget(_gallery(repository, child: _otherChild));
    await tester.pump();

    newResponse.complete(_page([_general(8, '새봄 그림')]));
    await tester.pumpAndSettle();
    oldResponse.complete(_page([_general(7, '도담 그림')]));
    await tester.pumpAndSettle();

    expect(find.text('새봄의 그림 전시관'), findsOneWidget);
    expect(find.text('새봄 그림'), findsOneWidget);
    expect(find.text('도담 그림'), findsNothing);
    expect(repository.requests.map((request) => request.$1), [7, 8]);
  });

  testWidgets('dispose 뒤 늦은 history 응답은 상태를 변경하지 않는다', (tester) async {
    final pending = Completer<ApiPage<ActivitySummaryDto>>();
    final repository = _FakeActivityRepository(
      handler: (_, _) => pending.future,
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(_page([_general(1, '늦은 그림')]));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('실제 그림 tap으로 크게 보고 시스템 back으로 목록에 돌아온다', (tester) async {
    final repository = _FakeActivityRepository(
      handler: (_, _) async =>
          _page([_general(1, '우리 가족'), _general(2, '무지개')]),
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();
    await _openFirstArtwork(tester, '우리 가족');

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.textContaining('참 멋지게 그렸다'), findsOneWidget);
    expect(find.bySemanticsLabel('다음 그림'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('내가 그린 그림 2점'), findsOneWidget);
  });

  testWidgets('보호자 분석·감정·리포트 정보는 아동 갤러리에 노출하지 않는다', (tester) async {
    final repository = _FakeActivityRepository(
      handler: (_, _) async => _page([
        _general(
          1,
          '안전한 제목',
          report: const ActivityReportSummaryDto(
            reportId: 77,
            reportStatus: 'COMPLETED',
          ),
        ),
      ]),
    );

    await tester.pumpWidget(_gallery(repository));
    await tester.pumpAndSettle();

    expect(find.text('안전한 제목'), findsOneWidget);
    expect(find.textContaining('AI 분석'), findsNothing);
    expect(find.textContaining('감정 분석'), findsNothing);
    expect(find.textContaining('보호자 리포트'), findsNothing);
    expect(find.textContaining('전문가'), findsNothing);
    expect(find.textContaining('진단'), findsNothing);
  });

  for (final scenario in <(Size, double)>[
    (const Size(320, 640), 1),
    (const Size(390, 844), 1),
    (const Size(844, 390), 1),
    (const Size(800, 1280), 1),
    (const Size(1280, 800), 1),
    (const Size(1600, 1000), 1),
    (const Size(390, 844), 2),
    (const Size(844, 390), 2),
  ]) {
    testWidgets('${scenario.$1.width.toInt()}x${scenario.$1.height.toInt()} '
        'textScale ${scenario.$2}에서 list detail scroll back overflow가 없다', (
      tester,
    ) async {
      _setViewport(tester, scenario.$1);
      addTearDown(() => _resetViewport(tester));
      final repository = _FakeActivityRepository(
        handler: (_, _) async =>
            _page([for (var i = 1; i <= 6; i++) _general(i, '지난 그림 $i')]),
      );

      await tester.pumpWidget(_gallery(repository, textScale: scenario.$2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('도담의 그림 전시관'), findsOneWidget);

      final scrollable = find.byKey(const ValueKey('child-gallery-scroll'));
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      await _openFirstArtwork(tester, '지난 그림 1');
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.bySemanticsLabel('뒤로 가기')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.bySemanticsLabel('뒤로 가기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
