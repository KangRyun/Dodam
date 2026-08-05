import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:dodam/features/drawing/presentation/widgets/canvas_tool_asset_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('crayon layers its registered point mask over the base artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CanvasToolAssetIcon(
          artwork: CanvasToolArtwork.crayon,
          pointColor: Colors.red,
          size: 64,
          filterQuality: FilterQuality.high,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('canvas-tool-base-crayon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('canvas-tool-mask-crayon')),
      findsOneWidget,
    );
    // 원화 규격대로 마스크의 명암을 두고 선택 색을 곱한다(S15P11B209-806).
    // 색으로 덮어쓰면 도구가 단색 덩어리가 되고 밑그림이 가장자리로 비친다.
    expect(find.byType(ShaderMask), findsNothing);

    final base = tester.widget<Image>(
      find.byKey(const ValueKey('canvas-tool-base-crayon')),
    );
    final mask = tester.widget<Image>(
      find.byKey(const ValueKey('canvas-tool-mask-crayon')),
    );
    expect(
      (base.image as AssetImage).assetName,
      'assets/canvas/tools/crayon_base.png',
    );
    expect(
      (mask.image as AssetImage).assetName,
      'assets/canvas/tools/masks/crayon_point.png',
    );
    expect(base.fit, BoxFit.contain);
    expect(mask.fit, BoxFit.contain);
    expect(base.alignment, Alignment.center);
    expect(mask.alignment, Alignment.center);
    expect(base.filterQuality, FilterQuality.high);
    expect(mask.filterQuality, FilterQuality.high);
    expect(base.color, isNull);
    expect(mask.color, Colors.red);
    expect(mask.colorBlendMode, BlendMode.modulate);
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

  testWidgets('changing point color keeps the crayon base path and geometry', (
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

    await pump(Colors.red);
    final redBase = tester.widget<Image>(
      find.byKey(const ValueKey('canvas-tool-base-crayon')),
    );
    final redMask = tester.widget<Image>(
      find.byKey(const ValueKey('canvas-tool-mask-crayon')),
    );

    await pump(Colors.blue);
    final blueBase = tester.widget<Image>(
      find.byKey(const ValueKey('canvas-tool-base-crayon')),
    );
    final blueMask = tester.widget<Image>(
      find.byKey(const ValueKey('canvas-tool-mask-crayon')),
    );

    expect(
      (blueBase.image as AssetImage).assetName,
      (redBase.image as AssetImage).assetName,
    );
    expect(blueBase.fit, redBase.fit);
    expect(blueBase.alignment, redBase.alignment);
    expect(blueBase.filterQuality, redBase.filterQuality);
    expect(blueMask.fit, redMask.fit);
    expect(blueMask.alignment, redMask.alignment);
    expect(blueMask.filterQuality, redMask.filterQuality);
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
