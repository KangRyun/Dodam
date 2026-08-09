import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../design_system/design_system.dart';
import '../../application/canvas_tutorial_controller.dart';
import '../models/canvas_tutorial_step_content.dart';
import 'canvas_tutorial_target_registry.dart';

/// Canvas 위에 얹는 아동용 도구 안내다.
///
/// 화면 가운데 카드로 설명만 읽히면 아이는 그 버튼이 어디 있는지 못 찾는다. 그래서
/// 지금 툴바에 있는 실제 도구를 밝게 남기고 그 옆에 교사 도다미가 말을 건다.
/// 서버 상태 전이와 오류 처리는 [CanvasTutorialController] 가 그대로 맡고, 이
/// 위젯은 현재 단계를 어디에 어떻게 보여 줄지만 정한다.
///
/// Canvas 캡처용 `RepaintBoundary` 밖에 놓아야 저장되는 그림에 안내가 섞이지
/// 않는다. 호출부가 화면 최상위 [Stack] 에 마지막 자식으로 둔다.
final class CanvasToolTutorialOverlay extends StatelessWidget {
  const CanvasToolTutorialOverlay(
    this.controller, {
    this.targets,
    this.practice,
    this.htpTrial = false,
    super.key,
  });

  final CanvasTutorialController controller;

  /// 가리킬 도구의 실제 위치를 알려 준다. 없으면 가운데 카드로만 안내한다.
  final CanvasTutorialTargetRegistry? targets;

  /// 아이가 그 도구를 실제로 써 봤는지 알려 준다. 없으면 체크를 보이지 않는다.
  final CanvasTutorialPracticeTracker? practice;

  /// 사람·나무·집 그림에서 안내를 위해 도구를 잠시 열어 둔 상태인지.
  final bool htpTrial;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, practice]),
    builder: (context, _) {
      if (!controller.isVisible) return const SizedBox.shrink();
      return Positioned.fill(
        key: const ValueKey('canvas-tool-tutorial'),
        child: _CoachMark(
          controller: controller,
          targets: targets,
          practice: practice,
          htpTrial: htpTrial,
        ),
      );
    },
  );
}

/// 카드가 이만큼도 못 들어가면 target 옆에 붙이지 않고 화면 가운데로 물러난다.
const double _minCardHeight = 168;

/// 안내 카드와 화면·target 사이 여백이다.
const double _cardGap = AppSpacing.sm;

/// 밝게 남기는 구멍을 도구보다 조금 넓게 잡는다. 버튼 테두리가 딤에 잘리면
/// 무엇을 가리키는지 흐려진다.
const double _spotlightHalo = 6;

final class _CoachMark extends StatefulWidget {
  const _CoachMark({
    required this.controller,
    required this.targets,
    required this.practice,
    required this.htpTrial,
  });

  final CanvasTutorialController controller;
  final CanvasTutorialTargetRegistry? targets;
  final CanvasTutorialPracticeTracker? practice;
  final bool htpTrial;

  @override
  State<_CoachMark> createState() => _CoachMarkState();
}

final class _CoachMarkState extends State<_CoachMark>
    with WidgetsBindingObserver {
  /// 이 오버레이 기준으로 바꾼 target 위치다.
  List<Rect> _holes = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleResolve();
  }

  @override
  void didUpdateWidget(covariant _CoachMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 단계가 넘어가면 가리킬 자리가 달라진다.
    _scheduleResolve();
  }

  @override
  void didChangeMetrics() {
    // 화면을 돌리거나 크기가 바뀌면 툴바 위치가 달라진다. 이전 rect 를 그대로
    // 두면 아무것도 없는 자리를 가리킨다.
    _scheduleResolve();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// target 위치는 배치가 끝난 뒤에야 알 수 있어 다음 프레임에 읽는다.
  void _scheduleResolve() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveTargets());
  }

  void _resolveTargets() {
    if (!mounted) return;
    final registry = widget.targets;
    final target = _content.target;
    final resolved = registry == null || target == null
        ? const <Rect>[]
        : _toLocal(registry.rectsOf(target));
    if (_sameRects(_holes, resolved)) return;
    setState(() => _holes = resolved);
  }

  List<Rect> _toLocal(List<Rect> globalRects) {
    if (globalRects.isEmpty) return const [];
    final renderObject = context.findRenderObject();
    final origin = renderObject is RenderBox && renderObject.attached
        ? renderObject.localToGlobal(Offset.zero)
        : Offset.zero;
    return [for (final rect in globalRects) rect.shift(-origin)];
  }

  static bool _sameRects(List<Rect> a, List<Rect> b) => listEquals<Rect>(a, b);

  CanvasTutorialStepContent get _content => CanvasTutorialStepContent.of(
    widget.controller.step,
    htpTrial: widget.htpTrial,
  );

  @override
  Widget build(BuildContext context) {
    final failed = widget.controller.hasError;
    // 오류 안내는 가리킬 자리가 없다. 딤만 덮고 가운데에서 다시 시도를 받는다.
    final holes = failed ? const <Rect>[] : _holes;
    return _SpotlightBarrier(
      holes: holes,
      // 안내 중에도 가리키는 버튼은 눌러 볼 수 있다. 나머지 화면은 막아 그림에
      // 원치 않는 선이 남지 않게 한다.
      passThroughHoles: !failed && _content.allowsTargetTap,
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _layout(context, constraints.biggest, holes, failed: failed),
      ),
    );
  }

  Widget _layout(
    BuildContext context,
    Size size,
    List<Rect> holes, {
    required bool failed,
  }) {
    final safeArea = MediaQuery.paddingOf(context);
    final focus = holes.isEmpty
        ? null
        : holes.reduce((a, b) => a.expandToInclude(b));

    if (focus != null) {
      // 가리키는 도구를 가리지 않도록 반대쪽에 붙인다.
      final below = focus.center.dy < size.height / 2;
      final available = below
          ? size.height - focus.bottom - _cardGap - safeArea.bottom - _cardGap
          : focus.top - _cardGap - safeArea.top - _cardGap;
      if (available >= _minCardHeight) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: safeArea.left + _cardGap,
              right: safeArea.right + _cardGap,
              top: below ? focus.bottom + _cardGap : null,
              bottom: below ? null : size.height - focus.top + _cardGap,
              child: Align(
                alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
                child: _constrain(context, available, failed: failed),
              ),
            ),
          ],
        );
      }
    }

    // target 을 못 찾았거나 옆에 놓을 자리가 없으면 가운데 카드로 물러난다.
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: safeArea.left + _cardGap,
            right: safeArea.right + _cardGap,
            top: safeArea.top + _cardGap,
            bottom: safeArea.bottom + _cardGap,
          ),
          child: Center(
            child: _constrain(
              context,
              math.max(
                _minCardHeight,
                size.height - safeArea.vertical - _cardGap * 2,
              ),
              failed: failed,
            ),
          ),
        ),
      ],
    );
  }

  /// 큰 글자 설정에서도 카드가 화면을 넘지 않도록 최대 높이를 주고 안을 스크롤한다.
  Widget _constrain(
    BuildContext context,
    double maxHeight, {
    required bool failed,
  }) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: 1120,
      maxHeight: math.max(_minCardHeight, maxHeight),
    ),
    child: SingleChildScrollView(
      key: const ValueKey('canvas-tutorial-card-scroll'),
      child: _card(context, maxHeight: maxHeight, failed: failed),
    ),
  );

  Widget _card(
    BuildContext context, {
    required double maxHeight,
    required bool failed,
  }) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, progress, child) => Opacity(
        opacity: progress.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - progress) * (reduceMotion ? 0 : 10)),
          child: child,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 실제 부모 폭의 약 28%, 사용 가능한 높이의 약 76%를 함께 기준으로
          // 잡는다. 화면 방향이나 기기 종류를 추측하지 않아도 좁은 창부터
          // 태블릿까지 전신이 자연스럽게 커지고 카드의 터치 영역은 침범하지 않는다.
          final widthFromParent = constraints.maxWidth * 0.28;
          final widthFromHeight = maxHeight * 0.76 * (799 / 985);
          final teacherWidth = math
              .min(widthFromParent.clamp(76.0, 320.0), widthFromHeight)
              .toDouble();

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Teacher(
                width: teacherWidth,
                // 단계가 바뀔 때 한 번만 콩 뛴다. 계속 움직이면 시선을 빼앗는다.
                hopToken: failed ? -1 : _content.stepNumber,
                reduceMotion: reduceMotion,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Bubble(
                  child: failed
                      ? _TutorialError(widget.controller)
                      : _TutorialStep(
                          controller: widget.controller,
                          content: _content,
                          practiced:
                              widget.practice?.isDone(_content.target) ?? false,
                          showPractice: widget.practice != null,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 교사 도다미다. 원본 비율을 지키고 잘리지 않게 담는다.
final class _Teacher extends StatelessWidget {
  const _Teacher({
    required this.width,
    required this.hopToken,
    required this.reduceMotion,
  });

  final double width;

  /// 이 값이 바뀔 때만 한 번 뛴다. 단계 번호를 넣는다.
  final int hopToken;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final teacher = ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * (985 / 799),
        child: Image.asset(
          'assets/canvas/tutorial/teacher.png',
          key: const ValueKey('canvas-tutorial-teacher'),
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
          // 그림을 못 읽어도 안내 글은 읽을 수 있어야 한다.
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ),
    );
    if (reduceMotion) return teacher;
    return TweenAnimationBuilder<double>(
      // 단계마다 새로 시작해야 그때 한 번 뛴다.
      key: ValueKey('canvas-tutorial-teacher-hop-$hopToken'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOut,
      builder: (context, progress, child) => Transform.translate(
        offset: Offset(0, -12 * math.sin(math.pi * progress.clamp(0, 1))),
        child: child,
      ),
      child: teacher,
    );
  }
}

/// 교사가 말하는 카드다. 교사 그림 배경과 같은 흰 면이라 둘이 한 덩어리로 읽힌다.
final class _Bubble extends StatelessWidget {
  const _Bubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('canvas-tutorial-bubble'),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: const Color(0xFFD8C9B5)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x245A4939),
          blurRadius: 12,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
  );
}

final class _TutorialStep extends StatelessWidget {
  const _TutorialStep({
    required this.controller,
    required this.content,
    required this.practiced,
    required this.showPractice,
  });

  final CanvasTutorialController controller;
  final CanvasTutorialStepContent content;

  /// 이 단계의 도구를 아이가 실제로 한 번 써 봤는지.
  final bool practiced;
  final bool showPractice;

  @override
  Widget build(BuildContext context) {
    final first = controller.step == CanvasTutorialStep.pen;
    final last = controller.step == CanvasTutorialStep.complete;
    final practiceLabel = showPractice ? content.practiceLabel : null;
    final praise = practiced ? content.practicePraise : null;
    return Semantics(
      container: true,
      label: '그림 도구 안내 ${content.stepNumber}단계, ${content.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '도담 선생님',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label,
                ),
              ),
              Text(
                '${content.stepNumber} / ${CanvasTutorialStepContent.stepCount}',
                style: AppTypography.label,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(content.title, style: AppTypography.titleLg),
          const SizedBox(height: AppSpacing.xs),
          // 해 본 뒤에는 같은 설명을 다시 읽히지 않고 칭찬으로 바꾼다.
          Text(praise ?? content.description, style: AppTypography.body),
          if (content.trialNotice case final notice?) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              notice,
              key: const ValueKey('canvas-tutorial-trial-notice'),
              style: AppTypography.label,
            ),
          ],
          if (practiceLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _PracticeCheck(label: practiceLabel, done: practiced),
          ],
          const SizedBox(height: AppSpacing.sm),
          _TutorialFooter(
            current: content.step.index,
            showPrevious: !first,
            nextLabel: last ? '그림 시작하기' : '다음',
            busy: controller.isBusy,
            onPrevious: () => unawaited(controller.previous()),
            onNext: () => unawaited(controller.next()),
            onSkip: () => unawaited(controller.skip()),
          ),
        ],
      ),
    );
  }
}

final class _TutorialFooter extends StatelessWidget {
  const _TutorialFooter({
    required this.current,
    required this.showPrevious,
    required this.nextLabel,
    required this.busy,
    required this.onPrevious,
    required this.onNext,
    required this.onSkip,
  });

  final int current;
  final bool showPrevious;
  final String nextLabel;
  final bool busy;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final stackActions = constraints.maxWidth < 430 || textScale >= 1.6;
      final actions = Wrap(
        key: const ValueKey('canvas-tutorial-footer-actions'),
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xxs,
        runSpacing: AppSpacing.xxs,
        children: [
          if (showPrevious)
            TextButton(
              key: const ValueKey('tutorial-previous'),
              onPressed: busy ? null : onPrevious,
              child: const Text('이전'),
            ),
          TextButton(
            key: const ValueKey('tutorial-skip'),
            onPressed: busy ? null : onSkip,
            child: const Text('건너뛰기'),
          ),
          _PastelNextButton(
            label: nextLabel,
            loading: busy,
            onPressed: busy ? null : onNext,
          ),
        ],
      );

      if (stackActions) {
        return Column(
          key: const ValueKey('canvas-tutorial-footer-stacked'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _StepDots(current: current),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        );
      }

      return Row(
        key: const ValueKey('canvas-tutorial-footer-row'),
        children: [
          _StepDots(current: current),
          const Spacer(),
          Flexible(child: actions),
        ],
      );
    },
  );
}

final class _PastelNextButton extends StatelessWidget {
  const _PastelNextButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final shape = StadiumBorder(
      side: BorderSide(
        color: enabled ? const Color(0xFFD9C98F) : AppColors.outline,
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ConstrainedBox(
        key: const ValueKey('tutorial-next'),
        constraints: const BoxConstraints(
          minWidth: AppSizes.minTouchTarget,
          minHeight: AppSizes.minTouchTarget,
        ),
        child: Material(
          color: enabled ? const Color(0xFFF7E6A2) : AppColors.disabled,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          elevation: 1,
          shadowColor: const Color(0x335A4939),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            customBorder: shape,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Color(0xFF575033),
                        ),
                      )
                    else ...[
                      Text(
                        label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: AppTypography.button.copyWith(
                          color: const Color(0xFF575033),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: Color(0xFF575033),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 이 단계에서 한 번 해 보면 좋은 일과 해냈는지 표시다.
///
/// 해내야 다음으로 갈 수 있는 조건이 아니다. 막으면 진행이 멈추고, 캔버스에 선을
/// 강제로 그리게 하면 아이 그림에 원치 않는 자국이 남는다.
final class _PracticeCheck extends StatelessWidget {
  const _PracticeCheck({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      label: done ? '$label 완료' : label,
      child: Row(
        key: const ValueKey('canvas-tutorial-practice'),
        children: [
          AnimatedScale(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            scale: done ? 1.1 : 1,
            child: DecoratedBox(
              key: ValueKey(
                done
                    ? 'canvas-tutorial-practice-done'
                    : 'canvas-tutorial-practice-todo',
              ),
              decoration: BoxDecoration(
                color: done ? AppColors.canvasSwatchGreen : AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: done
                      ? AppColors.canvasSwatchGreen
                      : AppColors.canvasBorder,
                  width: 2,
                ),
              ),
              child: SizedBox.square(
                dimension: 22,
                child: done
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: AppColors.surface,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(done ? '해 봤어요!' : label, style: AppTypography.label),
          ),
        ],
      ),
    );
  }
}

/// 몇 번째 단계인지 점으로 보여 준다. 지금 단계만 길쭉한 알약이 된다.
final class _StepDots extends StatelessWidget {
  const _StepDots({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Row(
      key: const ValueKey('canvas-tutorial-dots'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (
          var index = 0;
          index < CanvasTutorialStepContent.stepCount;
          index++
        )
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: index == current ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: index == current
                    ? AppColors.brandYellow
                    : AppColors.canvasBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}

final class _TutorialError extends StatelessWidget {
  const _TutorialError(this.controller);

  final CanvasTutorialController controller;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: '도구 안내를 불러오지 못했어요',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('도구 안내를 불러오지 못했어요', style: AppTypography.titleLg),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          '그림은 그대로 그릴 수 있어요. 연결을 확인하고 다시 시도해 주세요.',
          style: AppTypography.body,
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('tutorial-retry'),
          label: '다시 시도',
          variant: AppButtonVariant.child,
          isLoading: controller.isBusy,
          onPressed: controller.isBusy
              ? null
              : () => unawaited(controller.retry()),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          key: const ValueKey('tutorial-continue'),
          label: '그림 계속 그리기',
          variant: AppButtonVariant.quiet,
          onPressed: controller.isBusy ? null : controller.continueDrawing,
        ),
      ],
    ),
  );
}

/// 화면을 덮고 [holes] 만 밝게 남긴다.
///
/// 구멍은 그리기만 하는 게 아니라 실제 입력 경로도 함께 뚫는다. Canvas 좌표로
/// pointer event 를 새로 만들어 넘기면 gesture arena 와 접근성이 어긋나므로,
/// 구멍 안에서는 이 레이어가 hit test 를 사양해 원래 버튼이 직접 받게 한다.
final class _SpotlightBarrier extends SingleChildRenderObjectWidget {
  const _SpotlightBarrier({
    required this.holes,
    required this.passThroughHoles,
    super.child,
  });

  final List<Rect> holes;
  final bool passThroughHoles;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSpotlightBarrier(holes, passThroughHoles);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSpotlightBarrier renderObject,
  ) {
    renderObject
      ..holes = holes
      ..passThroughHoles = passThroughHoles;
  }
}

final class _RenderSpotlightBarrier extends RenderProxyBox {
  _RenderSpotlightBarrier(this._holes, this._passThroughHoles);

  List<Rect> _holes;
  bool _passThroughHoles;

  set holes(List<Rect> value) {
    if (listEquals(_holes, value)) return;
    _holes = value;
    markNeedsPaint();
  }

  set passThroughHoles(bool value) {
    if (_passThroughHoles == value) return;
    _passThroughHoles = value;
    markNeedsPaint();
  }

  /// 구멍 밖은 이 레이어가 받아 삼킨다. 안내 중에 캔버스가 그려지지 않게 한다.
  @override
  bool hitTestSelf(Offset position) =>
      !(_passThroughHoles && _holes.any((hole) => hole.contains(position)));

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final dim = Path()..addRect(offset & size);
    for (final hole in _holes) {
      dim.addRRect(_haloOf(hole).shift(offset));
    }
    dim.fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = AppColors.ink.withValues(alpha: .56));
    for (final hole in _holes) {
      final halo = _haloOf(hole).shift(offset);
      canvas
        ..drawRRect(
          halo,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = AppColors.brandYellow,
        )
        ..drawRRect(
          halo.inflate(2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = AppColors.canvasInk.withValues(alpha: .35),
        );
    }
    super.paint(context, offset);
  }

  static RRect _haloOf(Rect hole) => RRect.fromRectAndRadius(
    hole.inflate(_spotlightHalo),
    const Radius.circular(AppRadius.md),
  );
}
