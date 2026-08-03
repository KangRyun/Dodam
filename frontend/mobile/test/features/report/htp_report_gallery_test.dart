import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/report/data/dto/report_dtos.dart';
import 'package:dodam/features/report/domain/repositories/report_repository.dart';
import 'package:dodam/features/report/presentation/screens/report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _reportSessionId = 303;

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
  testWidgets('production AppRouter가 Report에 ActivityRepository를 주입한다', (
    tester,
  ) async {
    final activityRepository = _ActivityRepository(
      pages: {
        (3, 0): _page([_htpActivity(assessmentId: 91)]),
      },
    );

    await tester.pumpWidget(
      DodamApp(
        reportRepository: _ReportRepository(),
        activityRepository: activityRepository,
        initialRoute: AppRoutes.report('501'),
      ),
    );
    await tester.pumpAndSettle();

    expect(activityRepository.requests, [(3, 0)]);
    expect(find.byKey(const ValueKey('htp-report-gallery')), findsOneWidget);
  });

  testWidgets(
    'Report PERSON session이 속한 exact HTP 활동만 HOUSE→TREE→PERSON으로 표시한다',
    (tester) async {
      final activityRepository = _ActivityRepository(
        pages: {
          (3, 0): _page([
            _htpActivity(assessmentId: 11, reportSessionId: 999),
            _htpActivity(assessmentId: 91),
          ]),
        },
      );

      await _pumpReport(tester, activityRepository: activityRepository);
      await _pumpImages(tester);

      expect(activityRepository.requests, [(3, 0)]);
      expect(activityRepository.downloadedUrls, [
        '/api/v1/drawing-assets/91-house/file',
        '/api/v1/drawing-assets/91-tree/file',
        '/api/v1/drawing-assets/91-person/file',
      ]);
      expect(_subjectsInOrder(tester), ['HOUSE', 'TREE', 'PERSON']);
      expect(find.bySemanticsLabel('집 그림 단계'), findsOneWidget);
      expect(find.bySemanticsLabel('나무 그림 단계'), findsOneWidget);
      expect(find.bySemanticsLabel('사람 그림 단계'), findsOneWidget);
      for (final subject in const ['HOUSE', 'TREE', 'PERSON']) {
        final image = tester.widget<Image>(
          find.descendant(
            of: find.byKey(ValueKey('htp-report-image-$subject')),
            matching: find.byType(Image),
          ),
        );
        expect(image.fit, BoxFit.contain);
      }
    },
  );

  for (final subject in const ['HOUSE', 'TREE']) {
    testWidgets('Report $subject session도 exact HTP membership으로 세 장을 표시한다', (
      tester,
    ) async {
      final activityRepository = _ActivityRepository(
        pages: {
          (3, 0): _page([
            _htpActivity(assessmentId: 91, matchingSubject: subject),
          ]),
        },
      );

      await _pumpReport(tester, activityRepository: activityRepository);
      await _pumpImages(tester);

      expect(_subjectsInOrder(tester), ['HOUSE', 'TREE', 'PERSON']);
      expect(activityRepository.downloadedUrls, hasLength(3));
      expect(find.byKey(const ValueKey('report-image')), findsNothing);
    });
  }

  testWidgets('다음 페이지에서 exact session membership을 찾으면 즉시 pagination을 중단한다', (
    tester,
  ) async {
    final activityRepository = _ActivityRepository(
      pages: {
        (3, 0): _page(
          [_htpActivity(assessmentId: 11, reportSessionId: 999)],
          page: 0,
          totalPages: 3,
          hasNext: true,
        ),
        (3, 1): _page(
          [_htpActivity(assessmentId: 91)],
          page: 1,
          totalPages: 3,
          hasNext: true,
        ),
        (3, 2): _page(
          [_htpActivity(assessmentId: 92, reportSessionId: 929)],
          page: 2,
          totalPages: 3,
        ),
      },
    );

    await _pumpReport(tester, activityRepository: activityRepository);

    expect(activityRepository.requests, [(3, 0), (3, 1)]);
    expect(find.byKey(const ValueKey('htp-report-gallery')), findsOneWidget);
  });

  testWidgets('끝까지 exact session이 없으면 기존 Report 단일 이미지로 fallback한다', (
    tester,
  ) async {
    final reportRepository = _ReportRepository();
    final activityRepository = _ActivityRepository(
      pages: {
        (3, 0): _page(
          [_htpActivity(assessmentId: 11, reportSessionId: 999)],
          page: 0,
          totalPages: 2,
          hasNext: true,
        ),
        (3, 1): _page(const [], page: 1, totalPages: 2),
      },
    );

    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
    );
    await _pumpImages(tester);

    expect(activityRepository.requests, [(3, 0), (3, 1)]);
    expect(find.byKey(const ValueKey('htp-report-gallery')), findsNothing);
    expect(find.byKey(const ValueKey('report-image')), findsOneWidget);
    expect(reportRepository.downloadedUrls, [
      '/api/v1/drawing-assets/representative/file',
    ]);
    expect(find.text('오늘 그림 이야기를 들려줄래?'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-home-cta')), findsOneWidget);
  });

  testWidgets('Report session ID가 null이면 history 없이 기존 단일 이미지로 fallback한다', (
    tester,
  ) async {
    final reportRepository = _ReportRepository(
      reports: {501: _htpReport(sessionId: null)},
    );
    final activityRepository = _ActivityRepository();

    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
    );
    await _pumpImages(tester);

    expect(activityRepository.requests, isEmpty);
    expect(find.byKey(const ValueKey('htp-report-gallery')), findsNothing);
    expect(find.byKey(const ValueKey('report-image')), findsOneWidget);
  });

  testWidgets('서로 다른 HTP 항목이 같은 session ID를 포함하면 단일 이미지로 fallback한다', (
    tester,
  ) async {
    final reportRepository = _ReportRepository();
    final activityRepository = _ActivityRepository(
      pages: {
        (3, 0): _page([
          _htpActivity(assessmentId: 91),
          _htpActivity(assessmentId: 92),
        ]),
      },
    );

    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
    );
    await _pumpImages(tester);

    expect(activityRepository.downloadedUrls, isEmpty);
    expect(find.byKey(const ValueKey('htp-report-gallery')), findsNothing);
    expect(find.byKey(const ValueKey('report-image')), findsOneWidget);
  });

  testWidgets('htpDrawings가 빈 HTP 항목뿐이면 unrelated 그림 대신 단일 이미지로 fallback한다', (
    tester,
  ) async {
    final reportRepository = _ReportRepository();
    final empty = _htpActivity(assessmentId: 91, drawings: const []);
    final activityRepository = _ActivityRepository(
      pages: {
        (3, 0): _page([empty]),
      },
    );

    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
    );
    await _pumpImages(tester);

    expect(find.byKey(const ValueKey('htp-report-gallery')), findsNothing);
    expect(find.byKey(const ValueKey('report-image')), findsOneWidget);
    expect(activityRepository.downloadedUrls, isEmpty);
  });

  testWidgets('중복 subject는 첫 장만 쓰고 누락·unknown은 카드별 fallback한다', (tester) async {
    final activityRepository = _ActivityRepository(
      pages: {
        (3, 0): _page([
          _htpActivity(
            assessmentId: 91,
            drawings: const [
              HtpActivityDrawingDto(
                drawingSubject: 'HOUSE',
                drawingSessionId: 301,
                thumbnailUrl: '/api/v1/first-house',
              ),
              HtpActivityDrawingDto(
                drawingSubject: 'HOUSE',
                drawingSessionId: 302,
                thumbnailUrl: '/api/v1/duplicate-house',
              ),
              HtpActivityDrawingDto(
                drawingSubject: 'ALIEN',
                drawingSessionId: 999,
                thumbnailUrl: '/api/v1/unknown',
              ),
              HtpActivityDrawingDto(
                drawingSubject: 'PERSON',
                drawingSessionId: _reportSessionId,
                thumbnailUrl: '/api/v1/person',
              ),
            ],
          ),
        ]),
      },
    );

    await _pumpReport(tester, activityRepository: activityRepository);
    await _pumpImages(tester);

    expect(activityRepository.downloadedUrls, [
      '/api/v1/first-house',
      '/api/v1/person',
    ]);
    expect(find.text('나무 그림을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('ALIEN'), findsNothing);
  });

  testWidgets('history 응답 전에는 세 단계 loading 상태를 표시한다', (tester) async {
    final pending = Completer<ApiPage<ActivitySummaryDto>>();
    final activityRepository = _ActivityRepository(
      loaders: {(3, 0): () => pending.future},
    );

    await _pumpReport(
      tester,
      activityRepository: activityRepository,
      settle: false,
    );

    expect(find.bySemanticsLabel('집 그림 불러오는 중'), findsOneWidget);
    expect(find.bySemanticsLabel('나무 그림 불러오는 중'), findsOneWidget);
    expect(find.bySemanticsLabel('사람 그림 불러오는 중'), findsOneWidget);
    pending.complete(_page([_htpActivity(assessmentId: 91)]));
    await tester.pumpAndSettle();
  });

  testWidgets('한 장 요청 실패와 한 장 decode 실패가 나머지 성공 이미지를 숨기지 않는다', (tester) async {
    final activityRepository = _ActivityRepository(
      pages: {
        (3, 0): _page([_htpActivity(assessmentId: 91)]),
      },
      imageResults: {
        '/api/v1/drawing-assets/91-house/file': StateError('401'),
        '/api/v1/drawing-assets/91-tree/file': Uint8List.fromList([1, 2, 3]),
      },
    );

    await _pumpReport(tester, activityRepository: activityRepository);
    await _pumpImages(tester);

    expect(find.text('집 그림을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('나무 그림을 불러오지 못했어요.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('htp-report-image-PERSON')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('세 이미지가 모두 실패해도 분석 본문과 CTA를 유지한다', (tester) async {
    final activityRepository = _ActivityRepository(
      pages: {
        (3, 0): _page([_htpActivity(assessmentId: 91)]),
      },
      imageResults: {
        for (final subject in const ['house', 'tree', 'person'])
          '/api/v1/drawing-assets/91-$subject/file': StateError('500'),
      },
    );

    await _pumpReport(tester, activityRepository: activityRepository);
    await _pumpImages(tester);

    expect(find.textContaining('그림을 불러오지 못했어요.'), findsNWidgets(3));
    expect(find.text('오늘 그림 이야기를 들려줄래?'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-home-cta')), findsOneWidget);
  });

  testWidgets('history API 실패는 기존 단일 이미지로 fallback하고 Report를 막지 않는다', (
    tester,
  ) async {
    final reportRepository = _ReportRepository();
    final activityRepository = _ActivityRepository(
      historyFailure: StateError('offline'),
    );

    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
    );
    await _pumpImages(tester);

    expect(find.byKey(const ValueKey('htp-report-gallery')), findsNothing);
    expect(find.byKey(const ValueKey('report-image')), findsOneWidget);
    expect(reportRepository.downloadedUrls, [
      '/api/v1/drawing-assets/representative/file',
    ]);
    expect(find.text('오늘 그림 이야기를 들려줄래?'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-home-cta')), findsOneWidget);
  });

  testWidgets('동일 identity rebuild는 history 요청을 중복 생성하지 않는다', (tester) async {
    final activityRepository = _ActivityRepository(
      pages: {
        (3, 0): _page([_htpActivity(assessmentId: 91)]),
      },
    );
    final reportRepository = _ReportRepository();

    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
    );
    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
      resetView: false,
    );

    expect(reportRepository.calls, [501]);
    expect(activityRepository.requests, [(3, 0)]);
  });

  testWidgets('childId 변경 후 늦은 이전 history 응답은 최신 아동 gallery를 덮지 않는다', (
    tester,
  ) async {
    final oldPending = Completer<ApiPage<ActivitySummaryDto>>();
    final activityRepository = _ActivityRepository(
      pages: {
        (4, 0): _page([
          _htpActivity(
            assessmentId: 94,
            reportSessionId: 403,
            childPrefix: 'child4',
          ),
        ]),
      },
      loaders: {(3, 0): () => oldPending.future},
    );
    final reportRepository = _ReportRepository(
      reports: {
        501: _htpReport(),
        502: _htpReport(reportId: 502, childId: 4, sessionId: 403),
      },
    );

    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
      settle: false,
    );
    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
      reportId: '502',
      resetView: false,
    );
    oldPending.complete(_page([_htpActivity(assessmentId: 91)]));
    await _pumpImages(tester);

    expect(activityRepository.downloadedUrls, [
      '/api/v1/child4-94-house',
      '/api/v1/child4-94-tree',
      '/api/v1/child4-94-person',
    ]);
  });

  testWidgets('assessment를 확정하는 session 변경 시 늦은 이전 응답을 폐기한다', (tester) async {
    final oldPending = Completer<ApiPage<ActivitySummaryDto>>();
    final activityRepository = _ActivityRepository(
      loaders: {(3, 0): () => oldPending.future},
    );
    final reportRepository = _ReportRepository(
      reports: {
        501: _htpReport(),
        502: _htpReport(reportId: 502, sessionId: 503),
      },
    );

    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
      settle: false,
    );
    activityRepository.loaders.remove((3, 0));
    activityRepository.pages[(3, 0)] = _page([
      _htpActivity(
        assessmentId: 95,
        reportSessionId: 503,
        childPrefix: 'assessment95',
      ),
    ]);
    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
      reportId: '502',
      resetView: false,
    );
    oldPending.complete(_page([_htpActivity(assessmentId: 91)]));
    await _pumpImages(tester);

    expect(activityRepository.downloadedUrls, [
      '/api/v1/assessment95-95-house',
      '/api/v1/assessment95-95-tree',
      '/api/v1/assessment95-95-person',
    ]);
  });

  testWidgets('dispose 이후 늦은 history 응답은 상태나 예외를 만들지 않는다', (tester) async {
    final pending = Completer<ApiPage<ActivitySummaryDto>>();
    final activityRepository = _ActivityRepository(
      loaders: {(3, 0): () => pending.future},
    );

    await _pumpReport(
      tester,
      activityRepository: activityRepository,
      settle: false,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_page([_htpActivity(assessmentId: 91)]));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(activityRepository.downloadedUrls, isEmpty);
  });

  testWidgets('일반 그림 Report는 기존 단일 preview와 Report image fetcher만 사용한다', (
    tester,
  ) async {
    final activityRepository = _ActivityRepository();
    final reportRepository = _ReportRepository(
      reports: {501: _generalReport()},
    );

    await _pumpReport(
      tester,
      reportRepository: reportRepository,
      activityRepository: activityRepository,
    );
    await _pumpImages(tester);

    expect(find.byKey(const ValueKey('report-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('htp-report-gallery')), findsNothing);
    expect(activityRepository.requests, isEmpty);
    expect(reportRepository.downloadedUrls, [
      '/api/v1/drawing-assets/general/file',
    ]);
  });

  testWidgets('HTP gallery가 길어져도 스크롤 후 기존 Home CTA를 실제 tap할 수 있다', (
    tester,
  ) async {
    final activityRepository = _ActivityRepository(
      pages: {
        (3, 0): _page([_htpActivity(assessmentId: 91)]),
      },
    );

    await _pumpReport(
      tester,
      activityRepository: activityRepository,
      size: const Size(320, 640),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('report-home-cta')),
      400,
    );
    await tester.tap(find.byKey(const ValueKey('report-home-cta')));
    await tester.pumpAndSettle();

    expect(find.text('guardian home marker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final config in const [
    (name: '작은 휴대폰 textScale 2.0', size: Size(320, 640), scale: 2.0),
    (name: '태블릿 세로', size: Size(800, 1200), scale: 1.0),
    (name: '태블릿 가로', size: Size(1200, 800), scale: 1.0),
  ]) {
    testWidgets('${config.name}에서 gallery·본문·CTA가 overflow 없이 접근 가능하다', (
      tester,
    ) async {
      final activityRepository = _ActivityRepository(
        pages: {
          (3, 0): _page([_htpActivity(assessmentId: 91)]),
        },
      );

      await _pumpReport(
        tester,
        activityRepository: activityRepository,
        size: config.size,
        textScale: config.scale,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('report-home-cta')),
        400,
      );

      expect(find.byKey(const ValueKey('htp-report-gallery')), findsOneWidget);
      expect(find.byKey(const ValueKey('report-home-cta')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpReport(
  WidgetTester tester, {
  _ReportRepository? reportRepository,
  required ActivityRepository activityRepository,
  String reportId = '501',
  Size size = const Size(1200, 900),
  double textScale = 1,
  bool settle = true,
  bool resetView = true,
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
      routes: {
        AppRoutes.guardianHome: (_) =>
            const Scaffold(body: Text('guardian home marker')),
      },
      home: ReportScreen(
        key: const ValueKey('production-report-screen'),
        reportId: reportId,
        repository: reportRepository ?? _ReportRepository(),
        activityRepository: activityRepository,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

Future<void> _pumpImages(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

List<String> _subjectsInOrder(WidgetTester tester) => [
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'htp-report-preview-',
                ) &&
                !(widget.key! as ValueKey<String>).value.startsWith(
                  'htp-report-preview-label-',
                ),
          )
          .evaluate())
    (element.widget.key! as ValueKey<String>).value.split('-').last,
];

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
  int reportSessionId = _reportSessionId,
  String matchingSubject = 'PERSON',
  String childPrefix = 'drawing-assets',
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
  completedAt: '2026-08-03T00:10:00Z',
  activityKind: 'HTP',
  htpAssessmentId: assessmentId,
  htpStatus: 'COMPLETED',
  htpDrawings:
      drawings ??
      [
        HtpActivityDrawingDto(
          drawingSubject: 'HOUSE',
          drawingSessionId: matchingSubject == 'HOUSE'
              ? reportSessionId
              : assessmentId * 10 + 1,
          thumbnailUrl: childPrefix == 'drawing-assets'
              ? '/api/v1/drawing-assets/$assessmentId-house/file'
              : '/api/v1/$childPrefix-$assessmentId-house',
        ),
        HtpActivityDrawingDto(
          drawingSubject: 'TREE',
          drawingSessionId: matchingSubject == 'TREE'
              ? reportSessionId
              : assessmentId * 10 + 2,
          thumbnailUrl: childPrefix == 'drawing-assets'
              ? '/api/v1/drawing-assets/$assessmentId-tree/file'
              : '/api/v1/$childPrefix-$assessmentId-tree',
        ),
        HtpActivityDrawingDto(
          drawingSubject: 'PERSON',
          drawingSessionId: matchingSubject == 'PERSON'
              ? reportSessionId
              : assessmentId * 10 + 3,
          thumbnailUrl: childPrefix == 'drawing-assets'
              ? '/api/v1/drawing-assets/$assessmentId-person/file'
              : '/api/v1/$childPrefix-$assessmentId-person',
        ),
      ],
);

ReportDetailDto _htpReport({
  int reportId = 501,
  int childId = 3,
  int? sessionId = _reportSessionId,
}) => _report(
  reportId: reportId,
  childId: childId,
  sessionId: sessionId,
  drawingTypeCode: 'HTP',
  drawingTypeName: 'HTP 검사',
);

ReportDetailDto _generalReport() => _report(
  drawingTypeCode: 'ART_DIARY',
  drawingTypeName: '그림일기',
  drawing: const ReportDrawingDto(
    finalImageUrl: '/api/v1/drawing-assets/general/file',
    thumbnailUrl: null,
  ),
);

ReportDetailDto _report({
  int reportId = 501,
  int childId = 3,
  int? sessionId = _reportSessionId,
  required String drawingTypeCode,
  required String drawingTypeName,
  ReportDrawingDto drawing = const ReportDrawingDto(
    finalImageUrl: '/api/v1/drawing-assets/representative/file',
    thumbnailUrl: null,
  ),
}) => ReportDetailDto(
  reportId: reportId,
  reportVersion: 1,
  reportStatus: 'COMPLETED',
  drawingSession: ReportDrawingSessionDto(
    drawingSessionId: sessionId,
    childId: childId,
    drawingTypeCode: drawingTypeCode,
    drawingTypeName: drawingTypeName,
    title: 'HTP 관찰 기록',
    inputMethod: 'UPLOAD',
    startedAt: '2026-08-03T00:00:00Z',
    completedAt: '2026-08-03T00:10:00Z',
    durationMs: 600000,
  ),
  drawing: drawing,
  childExpression: null,
  activityFacts: null,
  conversationSummary: null,
  guardianConversationGuide: const ['오늘 그림 이야기를 들려줄래?'],
  limitations: const [],
  expertReview: null,
  createdAt: '2026-08-03T00:11:00Z',
);

final class _ActivityRepository implements ActivityRepository {
  _ActivityRepository({
    Map<(int, int), ApiPage<ActivitySummaryDto>>? pages,
    Map<(int, int), Future<ApiPage<ActivitySummaryDto>> Function()>? loaders,
    this.imageResults = const {},
    this.historyFailure,
  }) : pages = pages ?? {},
       loaders = loaders ?? {};

  final Map<(int, int), ApiPage<ActivitySummaryDto>> pages;
  final Map<(int, int), Future<ApiPage<ActivitySummaryDto>> Function()> loaders;
  final Map<String, Object> imageResults;
  final Object? historyFailure;
  final List<(int, int)> requests = [];
  final List<String> downloadedUrls = [];

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async {
    final key = (childId, filter.page);
    requests.add(key);
    if (historyFailure case final failure?) throw failure;
    final loader = loaders[key];
    if (loader != null) return loader();
    return pages[key] ?? _page(const []);
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

final class _ReportRepository implements ReportRepository {
  _ReportRepository({Map<int, ReportDetailDto>? reports})
    : reports = reports ?? {501: _htpReport()};

  final Map<int, ReportDetailDto> reports;
  final List<int> calls = [];
  final List<String> downloadedUrls = [];

  @override
  Future<ReportDetailDto> getReport(int reportId) async {
    calls.add(reportId);
    return reports[reportId] ?? _htpReport(reportId: reportId);
  }

  @override
  Future<Uint8List> downloadImage(String imageUrl) async {
    downloadedUrls.add(imageUrl);
    return _validPng;
  }

  @override
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  }) => throw UnimplementedError();

  @override
  Future<ReportGenerationStatusDto> getGenerationStatus(int reportId) =>
      throw UnimplementedError();

  @override
  Future<ReportGenerationStatusDto> regenerateReport(
    int reportId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<AnalysisStatusDto> getAnalysisStatus(int analysisId) =>
      throw UnimplementedError();

  @override
  Future<AnalysisAcceptedDto> retryAnalysis(
    int analysisId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<ReportExportDto> requestExport(
    int reportId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadExport(String downloadUrl) =>
      throw UnimplementedError();
}
