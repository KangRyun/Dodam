import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:dodam/features/drawing/presentation/widgets/canvas_tool_asset_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('crayon uses the artwork drawn for the selected colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CanvasToolAssetIcon(
          artwork: CanvasToolArtwork.crayon,
          pointColor: AppColors.canvasSwatchRed,
          size: 64,
          filterQuality: FilterQuality.high,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('canvas-tool-base-crayon')),
      findsOneWidget,
    );
    // 색을 코드에서 덧칠하지 않는다(S15P11B209-806). 한 장에 색을 씌우면
    // 마스크가 못 덮는 가장자리로 밑그림이 비쳐 다른 색 띠가 생긴다.
    expect(find.byType(ShaderMask), findsNothing);
    expect(
      find.byKey(const ValueKey('canvas-tool-mask-crayon')),
      findsNothing,
    );

    final base = tester.widget<Image>(
      find.byKey(const ValueKey('canvas-tool-base-crayon')),
    );
    expect(
      (base.image as AssetImage).assetName,
      'assets/canvas/tools/red/crayon.png',
    );
    expect(base.fit, BoxFit.contain);
    expect(base.alignment, Alignment.center);
    expect(base.filterQuality, FilterQuality.high);
    expect(base.color, isNull);
  });

  test('a colour off the quick palette falls back to the nearest artwork', () {
    expect(CanvasToolAssetIcon.variantFor(AppColors.canvasSwatchTeal), 'teal');
    // 팔레트에서 고른 중간색도 가장 가까운 그림을 쓴다.
    expect(CanvasToolAssetIcon.variantFor(const Color(0xFF1F6FD0)), 'blue');
    expect(CanvasToolAssetIcon.variantFor(const Color(0xFF101010)), 'charcoal');
  });

  testWidgets(
    'eraser and palette retain their fixed artwork without point masks',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              CanvasToolAssetIcon(
                artwork: CanvasToolArtwork.eraser,
                pointColor: Colors.red,
              ),
              CanvasToolAssetIcon(
                artwork: CanvasToolArtwork.palette,
                pointColor: Colors.blue,
              ),
            ],
          ),
        ),
      );

      expect(find.byType(ShaderMask), findsNothing);
      expect(
        find.byKey(const ValueKey('canvas-tool-mask-eraser')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('canvas-tool-mask-palette')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('canvas-tool-base-eraser')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('canvas-tool-base-palette')),
        findsOneWidget,
      );
    },
  );

  testWidgets('changing point color swaps in that colour artwork', (
    tester,
  ) async {
    Future<void> pump(Color color) => tester.pumpWidget(
      MaterialApp(
        home: CanvasToolAssetIcon(
          artwork: CanvasToolArtwork.crayon,
          pointColor: color,
          size: 64,
          filterQuality: FilterQuality.low,
        ),
      ),
    );

    await pump(AppColors.canvasSwatchRed);
    final redBase = tester.widget<Image>(
      find.byKey(const ValueKey('canvas-tool-base-crayon')),
    );

    await pump(AppColors.canvasSwatchBlue);
    final blueBase = tester.widget<Image>(
      find.byKey(const ValueKey('canvas-tool-base-crayon')),
    );

    // 색마다 그림이 다르지만 놓이는 방식은 같아야 아이콘이 흔들리지 않는다.
    expect(
      (redBase.image as AssetImage).assetName,
      'assets/canvas/tools/red/crayon.png',
    );
    expect(
      (blueBase.image as AssetImage).assetName,
      'assets/canvas/tools/blue/crayon.png',
    );
    expect(blueBase.fit, redBase.fit);
    expect(blueBase.alignment, redBase.alignment);
    expect(blueBase.filterQuality, redBase.filterQuality);
  });

  testWidgets(
    'a failed base decode uses the artwork-specific monochrome fallback',
    (tester) async {
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _FailingAssetBundle(),
          child: const MaterialApp(
            home: CanvasToolAssetIcon(
              artwork: CanvasToolArtwork.crayon,
              pointColor: Colors.red,
            ),
          ),
        ),
      );
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(Icons.draw_outlined));
      expect(icon.color, AppColors.canvasInk);
      expect(icon.size, 40);
    },
  );
}

final class _FailingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future<ByteData>.error(StateError('Unable to decode $key'));
}
