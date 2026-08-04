import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 최초 캐릭터 선택 안내에서 캐러셀만 밝게 남기는 Spotlight 오버레이
/// (S15P11B209-850).
///
/// 테두리만 두르던 기존 강조는 배경 장면(하늘·언덕·이젤)에 묻혀 어디를 만져야
/// 하는지 드러나지 않았다. 주변을 어둡게 덮고 캐러셀 자리만 뚫어, 아이의 시선과
/// 손이 그 안으로 모이게 한다.
///
/// 캐러셀을 다시 그리지 않는다. 아래에 이미 떠 있는 실제 캐러셀 하나만 조작
/// 대상이며, 이 위젯은 그 위에 얹히는 시각 + 입력 차단 층이다.
class CharacterCarouselSpotlight extends StatefulWidget {
  const CharacterCarouselSpotlight({
    required this.targetRect,
    required this.message,
    required this.secondaryMessage,
    required this.accent,
    required this.busy,
    required this.showNudge,
    this.messageKey,
    super.key,
  });

  /// 밝게 남길 캐러셀의 화면 좌표. 아직 재지 못했거나 크기가 0이면 아무것도
  /// 그리지 않는다 — 잘못된 자리에 구멍을 뚫는 것보다 아무 것도 없는 편이 낫다.
  final Rect? targetRect;

  /// 코치마크 본문. 조작 전/후 문구 전환은 호출자가 정한다.
  final String message;

  /// 코치마크 보조 안내. 비우면 표시하지 않는다.
  final String secondaryMessage;

  /// 강조 색. 실패 상태에서는 호출자가 오류 색을 넘긴다.
  final Color accent;

  /// 기존 debounce PATCH가 진행 중인지. 코치마크 안에 비차단 progress만 띄운다.
  ///
  /// 저장은 캐러셀 조작이 곧바로 예약한다(S843). 별도 확정 버튼은 두지 않는다.
  final bool busy;

  /// pulse ring과 좌우 유도 화살표를 보일지. 조작을 마친 뒤에는 낮춘다.
  final bool showNudge;

  /// 코치마크에 붙일 key. 기존 안내 key를 그대로 옮겨오기 위해 받는다.
  final Key? messageKey;

  /// 캐러셀 바깥으로 넓히는 여백. 캐릭터·이름·dots·화살표가 모두 들어가야 한다.
  static const double holePadding = 14;

  static const double holeRadius = 36;

  @override
  State<CharacterCarouselSpotlight> createState() =>
      _CharacterCarouselSpotlightState();
}

class _CharacterCarouselSpotlightState extends State<CharacterCarouselSpotlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  /// 접근성 설정으로 애니메이션을 끈 기기에서는 반복 애니메이션을 돌리지 않고
  /// 정적인 강조로 대체한다.
  bool _animationsEnabled = true;

  /// pulse를 유한 횟수만 돌린다.
  ///
  /// 무한 반복은 프레임을 영원히 예약해 화면이 쉬지 않고, 이 화면을 검증하는
  /// 테스트의 `pumpAndSettle`도 끝나지 않는다. 시선을 끌 만큼만 뛰고 멈춘 뒤,
  /// 상태가 바뀌면(문구 전환·실패 등) 다시 짧게 뛴다.
  static const int _maxPulseCycles = 6;
  int _pulseCycles = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addStatusListener(_onPulseStatus);
  }

  void _onPulseStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (!_animationsEnabled || _pulseCycles >= _maxPulseCycles) {
      _pulse.value = 0;
      return;
    }
    _pulseCycles++;
    _pulse.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant CharacterCarouselSpotlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 문구·상태가 바뀐 순간에 다시 시선을 끈다.
    if (oldWidget.message != widget.message ||
        oldWidget.showNudge != widget.showNudge) {
      _pulseCycles = 0;
    }
    _syncAnimation();
  }

  void _syncAnimation() {
    final enabled =
        !MediaQuery.disableAnimationsOf(context) && widget.showNudge;
    _animationsEnabled = enabled;
    if (!enabled) {
      if (_pulse.isAnimating) _pulse.stop();
      _pulse.value = 0;
      return;
    }
    if (!_pulse.isAnimating && _pulseCycles < _maxPulseCycles) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    // 반복 controller는 여기서 확실히 멈춘다.
    _pulse.removeStatusListener(_onPulseStatus);
    _pulse.stop();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.targetRect;
    if (target == null || target.isEmpty) return const SizedBox.shrink();

    final hole = Rect.fromLTRB(
      target.left - CharacterCarouselSpotlight.holePadding,
      target.top - CharacterCarouselSpotlight.holePadding,
      target.right + CharacterCarouselSpotlight.holePadding,
      target.bottom + CharacterCarouselSpotlight.holePadding,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final safe = MediaQuery.paddingOf(context);
        final textScale = MediaQuery.textScalerOf(context).scale(1);

        // 코치마크가 필요한 대략 높이(본문 + 보조 + 여백). 정확한 측정 없이도
        // 아래에 둘 자리가 있는지 판단할 수 있게 글자 배율만 반영한다.
        final coachReserve =
            (widget.secondaryMessage.isEmpty ? 64.0 : 92.0) *
            textScale.clamp(1.0, 2.0);
        final belowTop = hole.bottom + AppSpacing.sm;
        final bottomLimit = size.height - safe.bottom - AppSpacing.xs;
        final fitsBelow = belowTop + coachReserve <= bottomLimit;
        // 아래에 자리가 없으면 위로 올리되, 화면·SafeArea 밖으로 나가지 않게
        // 가둔다. 짧은 화면에서 위로 밀면 코치마크가 잘려 읽을 수 없다.
        final minTop = safe.top + AppSpacing.xs;
        final maxTop = (bottomLimit - coachReserve) < minTop
            ? minTop
            : bottomLimit - coachReserve;
        final coachTop =
            (fitsBelow ? belowTop : hole.top - AppSpacing.sm - coachReserve)
                .clamp(minTop, maxTop);

        return Stack(
          children: [
            // ── 시각: 구멍 뚫린 scrim. 입력은 건드리지 않는다.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('character-spotlight-scrim'),
                  painter: SpotlightScrimPainter(
                    hole: hole,
                    radius: CharacterCarouselSpotlight.holeRadius,
                  ),
                ),
              ),
            ),

            // ── 입력: 구멍 바깥 네 영역만 막는다. 구멍 안은 통과시켜 실제
            //    캐러셀의 화살표·swipe가 그대로 동작한다.
            ..._barriers(size, hole),

            // ── pulse ring (장식)
            Positioned.fromRect(
              rect: hole.inflate(2),
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      key: const ValueKey('character-spotlight-ring'),
                      painter: SpotlightPulseRingPainter(
                        progress: _animationsEnabled ? _pulse.value : 0,
                        color: widget.accent,
                        radius: CharacterCarouselSpotlight.holeRadius,
                        animating: _animationsEnabled,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── 좌우 유도 화살표 (장식)
            if (widget.showNudge) ..._guideArrows(hole),

            // ── 코치마크
            //
            // 안내 문구만 담고 조작 요소가 없다. 짧은 화면에서는 hole과 겹칠 수
            // 밖에 없으므로 pointer를 통과시켜 캐러셀 조작을 절대 막지 않는다.
            Positioned(
              top: coachTop,
              left: AppSpacing.md,
              right: AppSpacing.md,
              child: IgnorePointer(child: _coachMark(pointerOnTop: fitsBelow)),
            ),
          ],
        );
      },
    );
  }

  /// 구멍 바깥만 막는 네 영역. 화면 전체를 덮으면 캐러셀까지 막힌다.
  List<Widget> _barriers(Size size, Rect hole) {
    final top = hole.top.clamp(0.0, size.height);
    final bottom = hole.bottom.clamp(0.0, size.height);
    final left = hole.left.clamp(0.0, size.width);
    final right = hole.right.clamp(0.0, size.width);
    return [
      _barrier(
        const ValueKey('character-spotlight-barrier-top'),
        0,
        0,
        size.width,
        top,
      ),
      _barrier(
        const ValueKey('character-spotlight-barrier-bottom'),
        0,
        bottom,
        size.width,
        size.height - bottom,
      ),
      _barrier(
        const ValueKey('character-spotlight-barrier-left'),
        0,
        top,
        left,
        bottom - top,
      ),
      _barrier(
        const ValueKey('character-spotlight-barrier-right'),
        right,
        top,
        size.width - right,
        bottom - top,
      ),
    ];
  }

  Widget _barrier(
    Key key,
    double left,
    double top,
    double width,
    double height,
  ) => Positioned(
    key: key,
    left: left,
    top: top,
    width: width < 0 ? 0 : width,
    height: height < 0 ? 0 : height,
    // 튜토리얼 중 배경 CTA·뒤로가기가 실수로 눌리지 않게 흡수만 한다.
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: const SizedBox.expand(),
    ),
  );

  List<Widget> _guideArrows(Rect hole) {
    final centerY = hole.top + hole.height * 0.32;
    return [
      _guideArrow(
        const ValueKey('character-spotlight-nudge-left'),
        Icons.chevron_left_rounded,
        left: hole.left - 52,
        top: centerY,
        reverse: true,
      ),
      _guideArrow(
        const ValueKey('character-spotlight-nudge-right'),
        Icons.chevron_right_rounded,
        left: hole.right + 12,
        top: centerY,
        reverse: false,
      ),
    ];
  }

  Widget _guideArrow(
    Key key,
    IconData icon, {
    required double left,
    required double top,
    required bool reverse,
  }) => Positioned(
    left: left,
    top: top,
    // 장식이라 pointer와 낭독 모두 비운다. 실제 조작은 캐러셀의 화살표가 한다.
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final wave = _animationsEnabled
                ? (0.5 - (_pulse.value - 0.5).abs()) * 2
                : 0.0;
            final dx = (reverse ? -1 : 1) * wave * 10;
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Container(
            key: key,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.sunshine,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: AppColors.surface, size: 26),
          ),
        ),
      ),
    ),
  );

  Widget _coachMark({required bool pointerOnTop}) => Semantics(
    key: widget.messageKey,
    container: true,
    liveRegion: true,
    label: widget.secondaryMessage.isEmpty
        ? widget.message
        : '${widget.message} ${widget.secondaryMessage}',
    child: ExcludeSemantics(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            key: const ValueKey('character-spotlight-coach'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: widget.accent, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: Offset(0, pointerOnTop ? 6 : -6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.busy) ...[
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: widget.accent,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Flexible(
                      child: Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: widget.accent == AppColors.error
                              ? AppColors.error
                              : AppColors.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.secondaryMessage.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    widget.secondaryMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 화면 전체를 덮되 [hole]만 남기는 scrim.
///
/// `Path.combine(difference)` 한 번으로 그려 blur 같은 비싼 효과를 쓰지 않는다.
class SpotlightScrimPainter extends CustomPainter {
  const SpotlightScrimPainter({required this.hole, required this.radius});

  final Rect hole;
  final double radius;

  static const Color scrim = Color(0xB8121A26);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(hole, Radius.circular(radius));
    final cutout = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(cutout, Paint()..color = scrim);
    // 구멍 안쪽 흰 테두리 — 밝은 영역의 경계를 또렷하게 만든다.
    canvas.drawRRect(
      rrect.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.surface.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant SpotlightScrimPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.radius != radius;
}

/// 구멍 둘레에서 퍼져나가는 노란 pulse ring.
class SpotlightPulseRingPainter extends CustomPainter {
  const SpotlightPulseRingPainter({
    required this.progress,
    required this.color,
    required this.radius,
    required this.animating,
  });

  final double progress;
  final Color color;
  final double radius;
  final bool animating;

  @override
  void paint(Canvas canvas, Size size) {
    final base = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    if (!animating) {
      // 애니메이션이 꺼진 기기에서는 정적인 테두리 강조로 대체한다.
      canvas.drawRRect(
        base,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = color.withValues(alpha: 0.85),
      );
      return;
    }
    final spread = 20 * progress;
    final alpha = (1 - progress).clamp(0.0, 1.0) * 0.6;
    canvas.drawRRect(
      base.inflate(spread),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color.withValues(alpha: alpha),
    );
    canvas.drawRRect(
      base,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant SpotlightPulseRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.animating != animating;
}
