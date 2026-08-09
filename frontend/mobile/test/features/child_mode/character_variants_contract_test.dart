import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child_mode/data/child_home_intro_store.dart';
import 'package:dodam/features/child_mode/domain/dodam_costume.dart';
import 'package:dodam/features/child_mode/presentation/screens/child_mode_screens.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// S15P11B209-866에서 추가한 신규 도담이 3종의 계약.
///
/// 코드·라벨·asset 경로와 실제 PNG의 alpha까지 함께 못 박는다. 기존 스냅샷
/// 테스트는 `AssetImage.assetName` 문자열만 비교해서 파일이 없거나 이름이 틀려도
/// 통과하므로, bundle load와 decode를 여기서 직접 확인한다.
const _newVariants = <DodamCostume, (String, String)>{
  DodamCostume.explorer: (
    '탐험가 도담이',
    'assets/characters/costumes/dodami_explorer_profile.png',
  ),
  DodamCostume.ribbon: (
    '리본 도담이',
    'assets/characters/costumes/dodami_ribbon_profile.png',
  ),
  DodamCostume.prince: (
    '왕자 도담이',
    'assets/characters/costumes/dodami_prince_profile.png',
  ),
};

const _legacyOrder = <DodamCostume>[
  DodamCostume.base,
  DodamCostume.princess,
  DodamCostume.dino,
  DodamCostume.octopus,
];

const _child = ChildSummaryDto(
  childId: 7,
  nickname: '도담',
  birthDate: '2020-01-01',
  age: 6,
  profileImageUrl: null,
  preferredCharacter: null,
  questionDifficulty: 'EASY',
  tutorialStatus: 'DONE',
  relationshipType: 'PARENT',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

const _artDiary = DrawingTypeDto(
  drawingTypeId: 5,
  code: 'ART_DIARY',
  name: '그림일기',
  activityCategory: 'GENERAL',
  selectableBy: 'BOTH',
  recommendedAgeMin: 4,
  recommendedAgeMax: 12,
  guideText: '오늘 있었던 일을 그림으로 그려 볼까?',
  displayOrder: 1,
);

/// 캐러셀 표시에 필요한 두 호출만 응답하고 나머지는 명시적으로 실패한다.
final class _StubDrawingRepository implements DrawingRepository {
  static const drawingTypes = <DrawingTypeDto>[_artDiary];

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) async => ApiPage<DrawingTypeDto>(
    content: drawingTypes,
    page: 0,
    size: drawingTypes.length,
    totalElements: drawingTypes.length,
    totalPages: 1,
    hasNext: false,
  );

  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async => null;

  /// 이 테스트는 캐러셀 표시만 다룬다. 그 밖의 호출은 조용히 넘기지 않는다.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}은 이 테스트 범위가 아니다');
}

final class _SeenIntroStore implements ChildHomeIntroStore {
  @override
  Future<bool> hasSeen(int childId) async => true;

  @override
  Future<void> markSeen(int childId) async {}
}

/// alpha 스캔 결과.
final class _AlphaScan {
  const _AlphaScan({
    required this.width,
    required this.height,
    required this.fullyTransparent,
    required this.semiTransparent,
    required this.opaque,
    required this.contentWidth,
    required this.contentHeight,
  });

  final int width;
  final int height;
  final int fullyTransparent;
  final int semiTransparent;
  final int opaque;

  /// alpha > 0 인 픽셀을 모두 담는 최소 사각형 크기 = 실제 캐릭터 그림 크기.
  final int contentWidth;
  final int contentHeight;

  int get total => width * height;
  bool get hasRealTransparency => fullyTransparent > 0 || semiTransparent > 0;

  /// 프레임 높이에서 캐릭터가 차지하는 비율.
  double get fillHeight => contentHeight / height;

  /// `BoxFit.contain`으로 [box]에 담았을 때 화면에 보이는 캐릭터 높이.
  double renderedHeightIn(Size box) {
    final scale = math.min(box.width / width, box.height / height);
    return contentHeight * scale;
  }
}

/// asset bundle에서 읽어 실제로 decode한 뒤 픽셀 alpha와 그림 경계를 잰다.
Future<_AlphaScan> _scanAsset(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final bytes = data.buffer.asUint8List();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = raw!.buffer.asUint8List();
    final width = image.width;
    final height = image.height;
    var fully = 0;
    var semi = 0;
    var opaque = 0;
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width * 4;
      for (var x = 0; x < width; x++) {
        final alpha = pixels[row + x * 4 + 3];
        if (alpha == 0) {
          fully++;
          continue;
        }
        if (alpha == 255) {
          opaque++;
        } else {
          semi++;
        }
        // 완전 투명이 아닌 픽셀만 그림 경계에 포함한다.
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    return _AlphaScan(
      width: width,
      height: height,
      fullyTransparent: fully,
      semiTransparent: semi,
      opaque: opaque,
      contentWidth: maxX < 0 ? 0 : maxX - minX + 1,
      contentHeight: maxY < 0 ? 0 : maxY - minY + 1,
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}

Widget _wrap(Widget home, {TextScaler textScaler = TextScaler.noScaling}) =>
    MaterialApp(
      // MediaQuery는 MaterialApp 안에 둔다. 밖에 두면 MaterialApp이 view 기준
      // MediaQuery를 다시 삽입해 textScaler가 무효가 된다.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: home,
    );

Future<void> _pumpHome(WidgetTester tester, {TextScaler? textScaler}) async {
  await tester.pumpWidget(
    _wrap(
      ChildModeHomeScreen(
        child: _child,
        drawingRepository: _StubDrawingRepository(),
        introStore: _SeenIntroStore(),
      ),
      textScaler: textScaler ?? TextScaler.noScaling,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('신규 3종 코드 계약', () {
    test('전체 코스튬은 정확히 7종이다', () {
      expect(DodamCostume.values, hasLength(7));
    });

    test('기존 4종의 순서가 유지되고 신규 3종이 뒤에 append된다', () {
      expect(DodamCostume.values.take(4).toList(), _legacyOrder);
      expect(DodamCostume.values.skip(4).toList(), _newVariants.keys.toList());
      // 기존 테스트가 참조하는 index 3은 계속 OCTOPUS여야 한다.
      expect(DodamCostume.values[3], DodamCostume.octopus);
    });

    test('신규 3종의 코드·라벨·asset 경로가 확정 계약과 같다', () {
      const expectedCodes = {'EXPLORER', 'RIBBON', 'PRINCE'};
      expect(
        _newVariants.keys.map((costume) => costume.code).toSet(),
        expectedCodes,
      );
      _newVariants.forEach((costume, contract) {
        final (label, asset) = contract;
        expect(costume.label, label);
        expect(costume.asset, asset);
      });
    });

    test('신규 3종은 저장된 코드로 다시 복원된다', () {
      for (final costume in _newVariants.keys) {
        expect(DodamCostume.fromCode(costume.code), costume);
      }
    });

    test('기존 4종의 asset 경로는 바뀌지 않는다', () {
      expect(
        DodamCostume.base.asset,
        'assets/characters/costumes/dodam_base.png',
      );
      expect(
        DodamCostume.princess.asset,
        'assets/characters/costumes/dodam_princess.png',
      );
      expect(
        DodamCostume.dino.asset,
        'assets/characters/costumes/dodam_dino.png',
      );
      expect(
        DodamCostume.octopus.asset,
        'assets/characters/costumes/dodam_octopus.png',
      );
    });
  });

  group('신규 3종 asset 계약', () {
    for (final entry in _newVariants.entries) {
      final costume = entry.key;
      test(
        '${costume.code} PNG은 bundle에서 load·decode되고 실제 투명 픽셀을 가진다',
        () async {
          final scan = await _scanAsset(costume.asset);

          // decode 성공 = 유효한 크기의 이미지가 나왔다.
          expect(scan.width, greaterThan(0));
          expect(scan.height, greaterThan(0));
          expect(
            scan.total,
            scan.fullyTransparent + scan.semiTransparent + scan.opaque,
          );

          // 캐러셀은 배경 장면 위에 캐릭터를 얹으므로 실제 투명 영역이 있어야 한다.
          expect(
            scan.hasRealTransparency,
            isTrue,
            reason: '${costume.code}에 투명 픽셀이 없으면 언덕 배경을 사각형으로 가린다',
          );
          expect(scan.fullyTransparent, greaterThan(0));

          // 완전히 투명하기만 한 이미지는 캐릭터가 보이지 않는다.
          expect(scan.opaque, greaterThan(0));
        },
      );
    }

    /// 신규 PNG는 원본이 정사각 프레임에 투명 여백을 크게 두고 있어, 그대로 쓰면
    /// `BoxFit.contain` 아래에서 기존 4종보다 작게 보였다. production 복사본은
    /// 완전 투명 바깥 픽셀만 trim하고 4% 여백을 다시 붙여 정규화했다.
    test('신규 3종의 캐릭터 점유 비율이 기존 4종 범위에 들어온다', () async {
      final fills = <DodamCostume, double>{};
      for (final costume in DodamCostume.values) {
        fills[costume] = (await _scanAsset(costume.asset)).fillHeight;
      }
      final legacy = _legacyOrder.map((c) => fills[c]!).toList();
      final legacyMin = legacy.reduce(math.min);

      for (final costume in _newVariants.keys) {
        expect(
          fills[costume]!,
          greaterThanOrEqualTo(legacyMin - 0.02),
          reason:
              '${costume.code} 점유율 ${fills[costume]} 이 기존 최소 $legacyMin 보다 '
              '크게 낮으면 캐러셀에서 눈에 띄게 작게 보인다',
        );
        expect(fills[costume]!, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('7종 캐러셀 표시 계약', () {
    testWidgets('320px 캐러셀에서 신규 3종의 렌더 크기가 기존 4종 범위에 들어온다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);

      await _pumpHome(tester);

      // 캐러셀 페이지(stage) 박스를 실제 레이아웃에서 잰다. 안쪽 `Image` 박스를
      // 직접 재지 않는 이유: 위젯 테스트는 asset을 decode하지 않아 `Image`의
      // intrinsic 크기가 없고 폭 0으로 배치된다(precache는 느리고 불안정하다).
      //
      // stage 박스를 써도 결론은 같다. 7종 모두 `contain`에서 폭이 제한 변이라
      // scale = boxW/frameW 이므로 렌더 높이는 contentH/frameW 에 비례하고,
      // 코스튬 사이의 상대 비교는 박스 크기와 무관해진다.
      final imageBox = tester.getSize(
        find.byKey(ValueKey('costume-stage-${DodamCostume.values.first.code}')),
      );
      expect(imageBox.width, greaterThan(0));
      expect(imageBox.height, greaterThan(0));

      // asset decode는 실제 async I/O다. `testWidgets`의 fake async zone에서는
      // 영원히 끝나지 않으므로 `runAsync`로 감싼다.
      final scans = <DodamCostume, _AlphaScan>{};
      await tester.runAsync(() async {
        for (final costume in DodamCostume.values) {
          scans[costume] = await _scanAsset(costume.asset);
        }
      });
      expect(scans, hasLength(DodamCostume.values.length));

      // 상대 비교가 성립하려면 7종 모두 폭이 제한 변이어야 한다.
      for (final costume in DodamCostume.values) {
        final scan = scans[costume]!;
        expect(
          imageBox.width / scan.width,
          lessThan(imageBox.height / scan.height),
          reason: '${costume.code}이 높이 제한이면 이 비교 전제가 깨진다',
        );
      }

      final rendered = <DodamCostume, double>{
        for (final costume in DodamCostume.values)
          costume: scans[costume]!.renderedHeightIn(imageBox),
      };
      final legacy = _legacyOrder.map((c) => rendered[c]!).toList();
      final legacyMin = legacy.reduce(math.min);
      final legacyMax = legacy.reduce(math.max);

      // 기존 4종끼리도 편차가 있으므로 그 범위에 5% 여유만 준다.
      for (final costume in _newVariants.keys) {
        expect(
          rendered[costume]!,
          inInclusiveRange(legacyMin * 0.95, legacyMax * 1.05),
          reason:
              '${costume.code} 렌더 높이 ${rendered[costume]} 가 기존 범위 '
              '[$legacyMin, $legacyMax] 밖이면 캐러셀에서 크기가 튄다',
        );
      }
      expect(tester.takeException(), isNull);
    });

    const viewports = <String, Size>{
      '320x640': Size(320, 640),
      '390x844': Size(390, 844),
      '844x390': Size(844, 390),
      '800x1280': Size(800, 1280),
      '1280x800': Size(1280, 800),
      '1600x1000': Size(1600, 1000),
    };

    viewports.forEach((name, size) {
      testWidgets('$name에서 7개 indicator가 overflow 없이 모두 보인다', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        await _pumpHome(tester);

        for (final costume in DodamCostume.values) {
          expect(
            find.byKey(ValueKey('costume-indicator-${costume.code}')),
            findsOneWidget,
            reason: '$name에서 ${costume.code} indicator가 없다',
          );
        }
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('textScale 2.0에서도 7개 indicator가 overflow 없이 유지된다', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);

      await _pumpHome(tester, textScaler: const TextScaler.linear(2));

      for (final costume in DodamCostume.values) {
        expect(
          find.byKey(ValueKey('costume-indicator-${costume.code}')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('844x390 + textScale 2.0에서도 overflow가 없다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.reset);

      await _pumpHome(tester, textScaler: const TextScaler.linear(2));

      for (final costume in DodamCostume.values) {
        expect(
          find.byKey(ValueKey('costume-indicator-${costume.code}')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('캐러셀 페이지는 7종 전부를 담고 신규 3종도 넘겨서 볼 수 있다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await _pumpHome(tester);

      final pageView = tester.widget<PageView>(
        find.byKey(const ValueKey('costume-carousel')),
      );
      expect(pageView.controller!.page, 0);

      // 7종 전부를 순서대로 실제로 넘겨 본다. 각 단계에서 라벨과 stage가 함께
      // 바뀌어야 하며, 신규 3종도 예외가 아니다.
      expect(find.text(DodamCostume.values.first.label), findsOneWidget);
      for (var i = 1; i < DodamCostume.values.length; i++) {
        await tester.tap(find.byKey(const ValueKey('costume-next')));
        await tester.pumpAndSettle();
        final costume = DodamCostume.values[i];
        expect(
          find.text(costume.label),
          findsOneWidget,
          reason: '${costume.code} 라벨이 캐러셀에 나타나지 않는다',
        );
        expect(
          find.byKey(ValueKey('costume-stage-${costume.code}')),
          findsOneWidget,
          reason: '${costume.code} stage가 캐러셀에 나타나지 않는다',
        );
        expect(
          tester
              .widget<PageView>(find.byKey(const ValueKey('costume-carousel')))
              .controller!
              .page,
          i.toDouble(),
        );
      }

      // 마지막 항목에서 한 번 더 넘기면 처음으로 순환한다.
      await tester.tap(find.byKey(const ValueKey('costume-next')));
      await tester.pumpAndSettle();
      expect(find.text(DodamCostume.base.label), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
