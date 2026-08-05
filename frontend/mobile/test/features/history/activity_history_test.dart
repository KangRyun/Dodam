import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Guardian Home에서 선택 아동의 활동 기록으로 진입한다', (tester) async {
    final repository = _ActivityRepository();
    await _openHistory(tester, repository);

    expect(repository.calls, 1);
    expect(repository.lastChildId, 3);
    expect(find.text('활동 기록'), findsWidgets);
    expect(find.byKey(const ValueKey('activity-120')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-121')), findsOneWidget);
    // 첫 활동이 자동 선택되어 우측 프리뷰에 나온다.
    await _revealHistoryWidget(
      tester,
      find.byKey(const ValueKey('activity-history-summary')),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('activity-history-summary')),
        matching: find.text('우리 가족'),
      ),
      findsOneWidget,
    );

    // 카드를 누르면 화면 이동 없이 우측 프리뷰가 그 활동으로 바뀐다.
    final smallLayout = find.byKey(
      const ValueKey('activity-history-small-layout'),
    );
    if (smallLayout.evaluate().isNotEmpty) {
      await tester.drag(smallLayout, const Offset(0, 2000));
      await tester.pumpAndSettle();
    }
    await _revealHistoryWidget(
      tester,
      find.byKey(const ValueKey('activity-121')),
    );
    await tester.tap(find.byKey(const ValueKey('activity-121')));
    await tester.pump();
    await _revealHistoryWidget(
      tester,
      find.byKey(const ValueKey('activity-history-summary')),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('activity-history-summary')),
        matching: find.text('비 오는 날'),
      ),
      findsOneWidget,
    );
    await _revealHistoryWidget(
      tester,
      find.byKey(const ValueKey('activity-history-list')),
    );
    expect(find.byKey(const ValueKey('activity-history-list')), findsOneWidget);
  });

  testWidgets('목록 Loading 상태를 표시한다', (tester) async {
    final pending = Completer<ApiPage<ActivitySummaryDto>>();
    final repository = _ActivityRepository(pending: pending);
    await _openHistoryDirect(tester, repository, settle: false);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('activity-history-loading')),
      findsOneWidget,
    );
    pending.complete(_page(_activities));
    await tester.pumpAndSettle();
  });

  testWidgets('목록 Empty 상태를 표시한다', (tester) async {
    await _openHistoryDirect(tester, _ActivityRepository(activities: const []));
    expect(
      find.byKey(const ValueKey('activity-history-empty')),
      findsOneWidget,
    );
  });

  testWidgets('목록 Error에서 Retry할 수 있다', (tester) async {
    final repository = _ActivityRepository(error: StateError('network'));
    await _openHistoryDirect(tester, repository);
    expect(
      find.byKey(const ValueKey('activity-history-error')),
      findsOneWidget,
    );

    repository.error = null;
    // 하단 탭이 생기면서 세로 여유가 줄었다. 같은 파일의 다른 이동처럼
    // 보이는 곳까지 스크롤한 뒤 누른다.
    await tester.ensureVisible(find.text('다시 시도'));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.byKey(const ValueKey('activity-history-list')), findsOneWidget);
  });

  testWidgets('지원되는 기간과 Drawing Type 필터만 Repository에 전달한다', (tester) async {
    final repository = _ActivityRepository();
    await _openHistoryDirect(tester, repository);

    await tester.tap(find.text('전체 기간'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('최근 30일').last);
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(repository.lastFilter?.from, isNotNull);
    expect(repository.lastFilter?.to, isNotNull);

    await tester.tap(find.text('전체 활동'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('자유화').last);
    await tester.pumpAndSettle();
    expect(repository.calls, 3);
    expect(repository.lastFilter?.drawingType, 'FREE_DRAWING');
  });

  // 개편 홈은 아이가 있으면 목록 조회가 첫 아이를 자동 선택하므로, "선택 없음"은
  // 곧 아이가 하나도 없는 경우다. 빈 목록으로 그 상태를 만든다.
  testWidgets('선택된 childId가 없으면 가짜 조회 없이 안내한다', (tester) async {
    final repository = _ActivityRepository();
    await tester.pumpWidget(
      DodamApp(
        childRepository: const _ChildRepository(children: []),
        activityRepository: repository,
        initialRoute: AppRoutes.activityHistory,
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.calls, 0);
    expect(
      find.byKey(const ValueKey('activity-history-no-child')),
      findsOneWidget,
    );
  });

  testWidgets('thumbnail 실패와 작은 화면에서도 목록과 요약을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(600, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 보호자 홈은 태블릿 전용 레이아웃이라 작은 화면에선 홈을 거치지 않고 이력 화면을
    // 직접 띄워 이력 화면의 반응형만 검증한다(홈은 첫 아이를 자동 선택).
    await _openHistoryDirect(tester, _ActivityRepository());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('activity-history-small-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-thumbnail-placeholder')),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('activity-history-list')), findsOneWidget);
  });

  testWidgets('뒤로가기는 Guardian Home으로 복귀한다', (tester) async {
    await _openHistory(tester, _ActivityRepository());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('보호자 홈'), findsWidgets);
  });

  testWidgets('HTP 활동은 집·나무·사람 그림을 한 미리보기에서 전환한다', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openHistoryDirect(
      tester,
      _ActivityRepository(activities: [_htpActivity]),
    );

    expect(find.text('집 1/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('htp-preview-next')));
    await tester.pump();
    expect(find.text('나무 2/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('htp-preview-next')));
    await tester.pump();
    expect(find.text('사람 3/3'), findsOneWidget);
  });

  testWidgets('기록 보관소 배너는 실제 활동 수를 표시하고 삭제 안내를 만들지 않는다', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openHistoryDirect(tester, _ActivityRepository());

    expect(
      find.byKey(const ValueKey('activity-history-archive-hero')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-history-scribe-frame')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-history-scribe')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('활동 기록을 정리하는 도담이'), findsOneWidget);
    expect(
      tester
          .widget<Image>(find.byKey(const ValueKey('activity-history-scribe')))
          .fit,
      BoxFit.contain,
    );
    expect(find.text('보호자 활동 기록'), findsOneWidget);
    expect(find.text('아이의 그림과 이야기를 한 권씩 소중히 모았어요.'), findsOneWidget);
    expect(find.text('2개의 기록'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activity-history-books-pattern')),
      findsOneWidget,
    );
    expect(find.textContaining('기록 삭제 시'), findsNothing);
    await _revealHistoryWidget(
      tester,
      find.byKey(const ValueKey('activity-history-open-page')),
    );
    expect(
      find.byKey(const ValueKey('activity-history-open-page')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('세이지 배너의 제목·설명·실제 기록 수는 AA 대비를 충족한다', (tester) async {
    await _openHistoryDirect(tester, _ActivityRepository());

    final hero = tester.widget<Container>(
      find.byKey(const ValueKey('activity-history-archive-hero')),
    );
    final heroDecoration = hero.decoration! as BoxDecoration;
    final heroBackground = heroDecoration.color!;
    expect(heroBackground.computeLuminance(), greaterThan(0.5));

    for (final label in const [
      '보호자 활동 기록',
      '활동 기록',
      '아이의 그림과 이야기를 한 권씩 소중히 모았어요.',
    ]) {
      final text = tester.widget<Text>(find.text(label));
      expect(
        _contrastRatio(text.style!.color!, heroBackground),
        greaterThanOrEqualTo(4.5),
        reason: '$label 텍스트 대비',
      );
    }

    final count = tester.widget<Container>(
      find.byKey(const ValueKey('activity-history-count')),
    );
    final countBackground = (count.decoration! as BoxDecoration).color!;
    final countText = tester.widget<Text>(find.text('2개의 기록'));
    expect(
      _contrastRatio(countText.style!.color!, countBackground),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('선택 카드·필터·그림·이동 버튼에 의미와 48dp 터치 영역을 제공한다', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await _openHistoryDirect(
      tester,
      _ActivityRepository(activities: [_htpActivity]),
    );

    expect(find.bySemanticsLabel('활동 기록'), findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('activity-filter-semantics-아동')),
          )
          .label,
      contains('아동 필터, 현재 도담이'),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('activity-semantics-122'))),
      matchesSemantics(
        label: '집·나무·사람 그림, 2026.07.20, 캔버스, 분석 완료, 집·나무·사람 그림',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    expect(find.bySemanticsLabel('도담이의 집·나무·사람 그림 집 그림'), findsOneWidget);
    expect(find.bySemanticsLabel('이전 그림'), findsOneWidget);
    expect(find.bySemanticsLabel('다음 그림'), findsOneWidget);
    for (final key in const ['htp-preview-previous', 'htp-preview-next']) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
    }

    semantics.dispose();
  });

  for (final configuration in const [
    (label: 'Pixel Tablet 1280×800', size: Size(1280, 800), scale: 1.0),
    (label: '낮은 가로 844×390', size: Size(844, 390), scale: 1.0),
    (label: '휴대전화 세로 390×844', size: Size(390, 844), scale: 1.0),
    (label: 'Pixel Tablet 큰 글자', size: Size(1280, 800), scale: 2.0),
    (label: '낮은 가로 큰 글자', size: Size(844, 390), scale: 2.0),
    (label: '휴대전화 세로 큰 글자', size: Size(390, 844), scale: 2.0),
  ]) {
    testWidgets('${configuration.label}에서 overflow 없이 기록과 CTA에 접근한다', (
      tester,
    ) async {
      tester.view.physicalSize = configuration.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = configuration.scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _openHistoryDirect(tester, _ActivityRepository());

      expect(
        find.byKey(const ValueKey('activity-history-archive-hero')),
        findsOneWidget,
      );
      expect(find.text('2개의 기록'), findsOneWidget);
      expect(find.text('아이의 그림과 이야기를 한 권씩 소중히 모았어요.'), findsOneWidget);
      final frameSize = tester.getSize(
        find.byKey(const ValueKey('activity-history-scribe-frame')),
      );
      if (configuration.size.width < 700) {
        expect(frameSize.width, inInclusiveRange(92, 112));
        expect(
          find.byKey(const ValueKey('activity-history-books-pattern')),
          findsNothing,
        );
      } else {
        expect(frameSize.width, inInclusiveRange(150, 176));
        expect(
          find.byKey(const ValueKey('activity-history-books-pattern')),
          findsOneWidget,
        );
      }
      expect(frameSize.aspectRatio, 1);
      await _revealHistoryWidget(
        tester,
        find.byKey(const ValueKey('activity-history-list')),
      );
      expect(
        find.byKey(const ValueKey('activity-history-list')),
        findsOneWidget,
      );
      final cta = find.byKey(const ValueKey('activity-report-cta'));
      await _revealHistoryWidget(tester, cta);
      expect(cta, findsOneWidget);
      expect(tester.getSize(cta).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull, reason: configuration.label);
    });
  }

  testWidgets('끝까지 스크롤하면 다음 페이지를 이어붙인다', (tester) async {
    final repository = _PagingActivityRepository(
      pages: [_pageItems(200, 12), _pageItems(300, 3)],
    );
    await _openHistoryPaging(
      tester,
      repository,
      viewport: const Size(1200, 800),
    );

    // 첫 페이지만 불러온 상태.
    expect(repository.requestedPages, [0]);
    expect(find.byKey(const ValueKey('activity-200')), findsOneWidget);

    // 목록 끝으로 스크롤하면 다음 페이지(page 1)를 이어서 불러온다.
    await tester.drag(
      find.byKey(const ValueKey('activity-history-list')),
      const Offset(0, -4000),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedPages, [0, 1]);
  });

  testWidgets('다음 페이지가 없으면 스크롤해도 더 부르지 않는다', (tester) async {
    final repository = _PagingActivityRepository(pages: [_pageItems(200, 6)]);
    await _openHistoryPaging(
      tester,
      repository,
      viewport: const Size(1200, 800),
    );

    expect(repository.requestedPages, [0]);

    await tester.drag(
      find.byKey(const ValueKey('activity-history-list')),
      const Offset(0, -4000),
    );
    await tester.pumpAndSettle();

    // hasNext=false이므로 page 1을 요청하지 않는다.
    expect(repository.requestedPages, [0]);
  });

  testWidgets('다음 페이지 로드 실패 시 재시도 버튼으로 다시 불러온다', (tester) async {
    final repository = _PagingActivityRepository(
      pages: [_pageItems(200, 2), _pageItems(300, 2)],
      loadMoreError: StateError('network'),
    );
    // 첫 페이지(2개)가 화면을 못 채워 다음 페이지를 자동으로 당기다 실패한다.
    await _openHistoryPaging(
      tester,
      repository,
      viewport: const Size(1200, 800),
    );

    expect(repository.requestedPages, [0, 1]);
    expect(
      find.byKey(const ValueKey('activity-history-load-more-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('activity-300')), findsNothing);

    repository.loadMoreError = null;
    await tester.tap(find.text('더 불러오기'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-300')), findsOneWidget);
  });

  group('상단 타이틀·미리보기 헤더(S15P11B209-948)', () {
    testWidgets('셸 기록 탭은 상단 타이틀을 두고 배너 제목은 서술형이다', (tester) async {
      await _openHistoryTab(tester, _ActivityRepository());

      expect(
        find.descendant(
          of: find.byType(AppTopBar),
          matching: find.text('활동 기록'),
        ),
        findsOneWidget,
      );
      expect(find.text('기록을 한 권씩 살펴봐요'), findsOneWidget);
      // 상단 타이틀과 배너 제목이 같은 말을 두 번 하지 않는다.
      expect(find.text('활동 기록'), findsOneWidget);
      // eyebrow·설명은 그대로 둔다.
      expect(find.text('보호자 활동 기록'), findsOneWidget);
      expect(find.text('아이의 그림과 이야기를 한 권씩 소중히 모았어요.'), findsOneWidget);
    });

    testWidgets('단독 라우트는 상단 타이틀이 없어 배너가 화면 이름을 말한다', (tester) async {
      await _openHistoryDirect(tester, _ActivityRepository());

      expect(find.byType(AppTopBar), findsNothing);
      expect(find.text('활동 기록'), findsOneWidget);
      expect(find.text('기록을 한 권씩 살펴봐요'), findsNothing);
    });

    testWidgets('미리보기 헤더는 히어로와 같은 밝은 배경에 어두운 글자를 쓴다', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _openHistoryDirect(
        tester,
        _ActivityRepository(activities: [_htpActivity]),
      );
      await _revealHistoryWidget(
        tester,
        find.byKey(const ValueKey('activity-history-summary')),
      );

      final heroBackground =
          (tester
                      .widget<Container>(
                        find.byKey(
                          const ValueKey('activity-history-archive-hero'),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      final header = tester.widget<Container>(
        find
            .ancestor(of: find.text('펼친 기록서'), matching: find.byType(Container))
            .first,
      );

      expect(header.color, heroBackground, reason: '히어로와 같은 배경');
      expect(header.color!.computeLuminance(), greaterThan(0.5));

      for (final label in const ['펼친 기록서', '집·나무·사람 그림']) {
        final text = tester.widget<Text>(
          find.descendant(
            of: find.byWidget(header),
            matching: find.text(label),
          ),
        );
        expect(
          _contrastRatio(text.style!.color!, header.color!),
          greaterThanOrEqualTo(4.5),
          reason: '$label 대비',
        );
      }

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byWidget(header),
          matching: find.byIcon(Icons.menu_book_rounded),
        ),
      );
      expect(
        _contrastRatio(icon.color!, header.color!),
        greaterThanOrEqualTo(3),
        reason: '책 아이콘 대비',
      );
    });
  });
}

/// 보호자 셸의 '기록' 탭을 연다. 단독 라우트([_openHistoryDirect])와 달리 셸이
/// 상단 페이지 타이틀을 제공한다.
Future<void> _openHistoryTab(
  WidgetTester tester,
  _ActivityRepository repository,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    DodamApp(
      childRepository: const _ChildRepository(),
      activityRepository: repository,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(InkWell, '기록'));
  await tester.pumpAndSettle();
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

/// 보호자 홈을 거쳐 활동 이력으로 들어간다. 홈에서의 이동 자체를 보는
/// 테스트만 쓴다.
Future<void> _openHistory(
  WidgetTester tester,
  _ActivityRepository repository,
) async {
  await tester.pumpWidget(
    DodamApp(
      childRepository: const _ChildRepository(),
      activityRepository: repository,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('child-3')));
  await tester.pump();
  // 개편된 보호자 홈은 최근 활동·마음 달력용으로 같은 레포에 활동을 미리 조회한다.
  // 이력 화면의 조회만 세도록 진입 직전에 카운터를 초기화한다.
  repository.reset();
  // 예전 '활동 이력 보기' 버튼은 대시보드 개편으로 사라졌다. 지금은 "최근 활동"
  // 카드의 "전체"가 같은 화면으로 보낸다.
  final entry = find.ancestor(
    of: find.text('전체'),
    matching: find.byType(InkWell),
  );
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

/// 활동 이력 화면만 보는 테스트용. 보호자 홈을 거치지 않아 대시보드가 같은
/// 레포에 넣는 조회가 섞이지 않는다. 아이는 목록을 불러온 뒤 자동 선택된다.
Future<void> _openHistoryDirect(
  WidgetTester tester,
  _ActivityRepository repository, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    DodamApp(
      childRepository: const _ChildRepository(),
      activityRepository: repository,
      initialRoute: AppRoutes.activityHistory,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _revealHistoryWidget(WidgetTester tester, Finder target) async {
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pump();
    return;
  }

  final lowHeightLayout = find.byKey(
    const ValueKey('activity-history-low-height-layout'),
  );
  for (
    var attempt = 0;
    attempt < 8 &&
        target.evaluate().isEmpty &&
        lowHeightLayout.evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.drag(lowHeightLayout, const Offset(0, -240));
    await tester.pumpAndSettle();
  }

  final smallLayout = find.byKey(
    const ValueKey('activity-history-small-layout'),
  );
  for (
    var attempt = 0;
    attempt < 12 &&
        target.evaluate().isEmpty &&
        smallLayout.evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.drag(smallLayout, const Offset(0, -240));
    await tester.pumpAndSettle();
  }
  for (
    var attempt = 0;
    attempt < 12 &&
        target.evaluate().isEmpty &&
        smallLayout.evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.drag(smallLayout, const Offset(0, 240));
    await tester.pumpAndSettle();
  }

  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pump();
  }
}

final class _ActivityRepository implements ActivityRepository {
  _ActivityRepository({
    List<ActivitySummaryDto>? activities,
    this.error,
    this.pending,
  }) : activities = activities ?? _activities;

  List<ActivitySummaryDto> activities;
  Object? error;
  final Completer<ApiPage<ActivitySummaryDto>>? pending;
  int calls = 0;
  int? lastChildId;
  ActivityFilterDto? lastFilter;

  /// 보호자 홈 대시보드가 넣은 조회 기록을 지운다.
  void reset() {
    calls = 0;
    lastChildId = null;
    lastFilter = null;
  }

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async {
    calls += 1;
    lastChildId = childId;
    lastFilter = filter;
    if (error case final error?) throw error;
    return pending?.future ?? _page(activities);
  }

  @override
  Future<void> deleteActivity(int activityId) async {}

  @override
  Future<ActivityDetailDto> getActivity(int activityId) =>
      throw UnimplementedError();

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadImage(String url) =>
      throw StateError('image fetch failed');
}

/// 활동 이력 화면을 단독으로 띄우되, 뷰포트를 지정해 레이아웃(좁은/넓은)을
/// 고정한다. 넓은 뷰포트(>=760)에선 목록이 자체 스크롤러가 되어 무한 스크롤
/// 검증이 단순해진다.
Future<void> _openHistoryPaging(
  WidgetTester tester,
  ActivityRepository repository, {
  required Size viewport,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    DodamApp(
      childRepository: const _ChildRepository(),
      activityRepository: repository,
      initialRoute: AppRoutes.activityHistory,
    ),
  );
  await tester.pumpAndSettle();
}

List<ActivitySummaryDto> _pageItems(int startId, int count) => [
  for (var i = 0; i < count; i++)
    _activity(startId + i, 'A${startId + i}', 'FREE_DRAWING', '자유화'),
];

/// 페이지 단위로 응답하는 저장소. `filter.page`에 해당하는 페이지를 돌려주고,
/// 마지막 페이지가 아니면 `hasNext=true`를 준다. [loadMoreError]가 있으면
/// 2페이지 이후(page>=1) 요청에서 던진다.
final class _PagingActivityRepository implements ActivityRepository {
  _PagingActivityRepository({required this.pages, this.loadMoreError});

  final List<List<ActivitySummaryDto>> pages;
  Object? loadMoreError;
  final List<int> requestedPages = [];

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async {
    requestedPages.add(filter.page);
    if (loadMoreError != null && filter.page >= 1) throw loadMoreError!;
    final index = filter.page;
    final content = index >= 0 && index < pages.length
        ? pages[index]
        : const <ActivitySummaryDto>[];
    return ApiPage(
      content: content,
      page: index,
      size: 20,
      totalElements: pages.fold<int>(0, (sum, p) => sum + p.length),
      totalPages: pages.length,
      hasNext: index < pages.length - 1,
    );
  }

  @override
  Future<void> deleteActivity(int activityId) async {}

  @override
  Future<ActivityDetailDto> getActivity(int activityId) =>
      throw UnimplementedError();

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadImage(String url) =>
      throw StateError('image fetch failed');
}

ApiPage<ActivitySummaryDto> _page(List<ActivitySummaryDto> activities) =>
    ApiPage(
      content: activities,
      page: 0,
      size: 20,
      totalElements: activities.length,
      totalPages: activities.isEmpty ? 0 : 1,
      hasNext: false,
    );

final _activities = [
  _activity(120, '우리 가족', 'ART_DIARY', '그림일기'),
  _activity(121, '비 오는 날', 'FREE_DRAWING', '자유화'),
];

const _htpActivity = ActivitySummaryDto(
  activityId: 122,
  title: null,
  drawingType: ActivityDrawingTypeDto(code: 'HTP', name: '집·나무·사람 그림'),
  inputMethod: 'CANVAS',
  sessionStatus: 'COMPLETED',
  selectedEmotions: ['CALM'],
  thumbnailUrl: '/api/v1/drawing-assets/33/file',
  analysisStatus: 'COMPLETED',
  report: null,
  startedAt: '2026-07-20T09:40:00Z',
  completedAt: '2026-07-20T10:03:00Z',
  activityKind: 'HTP',
  htpAssessmentId: 40,
  htpStatus: 'COMPLETED',
  htpDrawings: [
    HtpActivityDrawingDto(
      drawingSubject: 'HOUSE',
      drawingSessionId: 10,
      thumbnailUrl: '/api/v1/drawing-assets/31/file',
    ),
    HtpActivityDrawingDto(
      drawingSubject: 'TREE',
      drawingSessionId: 11,
      thumbnailUrl: '/api/v1/drawing-assets/32/file',
    ),
    HtpActivityDrawingDto(
      drawingSubject: 'PERSON',
      drawingSessionId: 12,
      thumbnailUrl: '/api/v1/drawing-assets/33/file',
    ),
  ],
);

ActivitySummaryDto _activity(int id, String title, String code, String name) =>
    ActivitySummaryDto(
      activityId: id,
      title: title,
      drawingType: ActivityDrawingTypeDto(code: code, name: name),
      inputMethod: 'CANVAS',
      sessionStatus: 'COMPLETED',
      selectedEmotions: const ['HAPPY'],
      thumbnailUrl: 'https://invalid.example/$id.png',
      analysisStatus: 'COMPLETED',
      report: null,
      startedAt: '2026-07-20T09:40:00Z',
      completedAt: '2026-07-20T10:03:00Z',
    );

final class _ChildRepository implements ChildRepository {
  const _ChildRepository({this.children = const [_child]});
  final List<ChildSummaryDto> children;
  @override
  Future<List<ChildSummaryDto>> getChildren() async => children;
  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) =>
      throw UnimplementedError();
  @override
  Future<void> deleteChild(int childId) => throw UnimplementedError();
  @override
  Future<ChildDetailDto> getChild(int childId) => throw UnimplementedError();
  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) =>
      throw UnimplementedError();
  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) => throw UnimplementedError();
}

const _child = ChildSummaryDto(
  childId: 3,
  nickname: '도담이',
  birthDate: '2019-03-14',
  age: 7,
  profileImageUrl: null,
  preferredCharacter: 'BEAR',
  questionDifficulty: 'PRESCHOOL',
  tutorialStatus: 'COMPLETED',
  relationshipType: 'MOTHER',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: '2026-07-20T08:15:00Z',
    totalActivityCount: 2,
  ),
);
