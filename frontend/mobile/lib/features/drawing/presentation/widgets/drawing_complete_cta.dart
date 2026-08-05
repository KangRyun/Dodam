import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 그림을 끝냈다고 알리는 화면 오른쪽 아래의 큰 버튼이다.
///
/// 툴바 안의 작은 아이콘이 아니라 AI 말풍선과 같은 크기·모양으로 둔다. 아이가
/// 마지막에 누를 것이 하나뿐이어야 하고, 도구 사이에 섞여 있으면 잘못 눌러
/// 그림을 끝내 버린다.
final class DrawingCompleteCta extends StatefulWidget {
  const DrawingCompleteCta({
    required this.enabled,
    required this.isCompleting,
    required this.onPressed,
    this.compact = false,
    super.key,
  });

  /// 보낼 그림이 있고 다른 전송이 진행 중이 아닌지.
  final bool enabled;

  /// 완료 전송이 진행 중인지. 진행 중에는 라벨과 표시를 바꾸고 다시 못 누른다.
  final bool isCompleting;
  final VoidCallback onPressed;

  /// 좁은 화면용 촘촘한 배치. 담긴 상자 높이로 스스로 판단하지 않는다.
  final bool compact;

  @override
  State<DrawingCompleteCta> createState() => _DrawingCompleteCtaState();
}

class _DrawingCompleteCtaState extends State<DrawingCompleteCta> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tappable = widget.enabled && !widget.isCompleting;
    final emphasized = tappable && (_hovered || _focused);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final label = widget.isCompleting ? '완성하는 중' : '다 그렸어요!';
    return KeyedSubtree(
      // 툴바에 있던 시절의 Key 둘을 그대로 쓴다. 완료 흐름을 검사하는 테스트가
      // 이 이름으로 버튼을 찾으므로 자리를 옮기더라도 이름은 바꾸지 않는다.
      key: const ValueKey('drawing-complete-button'),
      child: Semantics(
        label: widget.isCompleting ? '그림 완료 처리 중' : '그림 완료',
        button: true,
        enabled: tappable,
        onTap: tappable ? widget.onPressed : null,
        excludeSemantics: true,
        child: AnimatedScale(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          scale: emphasized ? 1.04 : 1,
          child: Opacity(
            opacity: tappable || widget.isCompleting ? 1 : .45,
            child: Material(
              // 툴바에 있던 시절의 Key다. 탭 대상 자체가 아니라 감싼 면에 둔다 -
              // 테스트가 이 Key 아래의 InkWell 을 찾아 활성 여부를 본다.
              key: const ValueKey('drawing-complete'),
              color: AppColors.canvasSwatchGreen,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              elevation: 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                excludeFromSemantics: true,
                canRequestFocus: tappable,
                mouseCursor: tappable
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                onHover: (value) {
                  if (_hovered != value) setState(() => _hovered = value);
                },
                onFocusChange: (value) {
                  if (_focused != value) setState(() => _focused = value);
                },
                onTap: tappable ? widget.onPressed : null,
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 64,
                    minWidth: 64,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? AppSpacing.md : AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.canvasInk, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isCompleting) ...[
                        const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.surface,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.surface,
                          fontSize: widget.compact ? 19 : 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
