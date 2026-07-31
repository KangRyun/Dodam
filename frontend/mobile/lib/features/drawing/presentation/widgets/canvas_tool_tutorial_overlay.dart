import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/canvas_tutorial_controller.dart';

/// Canvas 위에 표시되는 아동용 도구 안내다.
///
/// 서버 상태 전이와 오류 처리는 [CanvasTutorialController]에 맡기고, 이 위젯은
/// 현재 단계와 이동 동작만 표현한다. 작은 가로 화면에서도 카드 내부가
/// 스크롤되므로 실제 Canvas 레이아웃을 밀어내지 않는다.
final class CanvasToolTutorialOverlay extends StatelessWidget {
  const CanvasToolTutorialOverlay(this.controller, {super.key});

  final CanvasTutorialController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.isVisible) return const SizedBox.shrink();
      return Positioned.fill(
        key: const ValueKey('canvas-tool-tutorial'),
        child: Material(
          color: AppColors.ink.withValues(alpha: 0.56),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 520,
                    maxHeight: constraints.maxHeight - AppSpacing.lg,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: controller.hasError
                            ? _TutorialError(controller)
                            : _TutorialStep(controller),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

final class _TutorialStep extends StatelessWidget {
  const _TutorialStep(this.controller);

  final CanvasTutorialController controller;

  @override
  Widget build(BuildContext context) {
    final content = _contents[controller.step]!;
    final stepNumber = controller.step.index + 1;
    final last = controller.step == CanvasTutorialStep.complete;
    return Semantics(
      container: true,
      label: '그림 도구 안내 $stepNumber단계, ${content.title}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('tutorial-skip'),
              onPressed: controller.isBusy
                  ? null
                  : () => unawaited(controller.skip()),
              child: const Text('건너뛰기'),
            ),
          ),
          CircleAvatar(
            radius: 34,
            backgroundColor: content.background,
            child: Icon(content.icon, size: 36, color: content.foreground),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            content.title,
            textAlign: TextAlign.center,
            style: AppTypography.titleLg,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            content.description,
            textAlign: TextAlign.center,
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '$stepNumber / ${CanvasTutorialStep.values.length}',
            style: AppTypography.label,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              if (controller.step != CanvasTutorialStep.pen) ...[
                Expanded(
                  child: AppButton(
                    key: const ValueKey('tutorial-previous'),
                    label: '이전',
                    variant: AppButtonVariant.secondary,
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(controller.previous()),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: AppButton(
                  key: const ValueKey('tutorial-next'),
                  label: last ? '그림 시작하기' : '다음',
                  variant: AppButtonVariant.child,
                  isLoading: controller.isBusy,
                  onPressed: controller.isBusy
                      ? null
                      : () => unawaited(controller.next()),
                ),
              ),
            ],
          ),
        ],
      ),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircleAvatar(
          radius: 34,
          backgroundColor: AppColors.errorSoft,
          child: Icon(
            Icons.cloud_off_rounded,
            size: 36,
            color: AppColors.error,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          '도구 안내를 불러오지 못했어요',
          textAlign: TextAlign.center,
          style: AppTypography.titleLg,
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          '그림은 그대로 그릴 수 있어요. 연결을 확인하고 다시 시도해 주세요.',
          textAlign: TextAlign.center,
          style: AppTypography.body,
        ),
        const SizedBox(height: AppSpacing.lg),
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

final class _TutorialContent {
  const _TutorialContent({
    required this.icon,
    required this.title,
    required this.description,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color background;
  final Color foreground;
}

const _contents = <CanvasTutorialStep, _TutorialContent>{
  CanvasTutorialStep.pen: _TutorialContent(
    icon: Icons.edit_rounded,
    title: '연필로 그려요',
    description: '연필을 고른 뒤 손가락이나 펜으로 자유롭게 선을 그어 보세요.',
    background: AppColors.brandYellowSoft,
    foreground: AppColors.tangerine,
  ),
  CanvasTutorialStep.eraser: _TutorialContent(
    icon: Icons.auto_fix_normal_rounded,
    title: '지우개로 고쳐요',
    description: '지우개를 고르면 마음에 들지 않는 부분만 부드럽게 지울 수 있어요.',
    background: AppColors.leafSoft,
    foreground: AppColors.leaf,
  ),
  CanvasTutorialStep.color: _TutorialContent(
    icon: Icons.palette_rounded,
    title: '좋아하는 색을 골라요',
    description: '색상 동그라미를 눌러 지금 그리고 싶은 색으로 바꿔 보세요.',
    background: AppColors.tangerineSoft,
    foreground: AppColors.tangerine,
  ),
  CanvasTutorialStep.thickness: _TutorialContent(
    icon: Icons.line_weight_rounded,
    title: '선 굵기를 바꿔요',
    description: '가늘게, 보통, 굵게 중에서 그림에 어울리는 굵기를 골라 보세요.',
    background: AppColors.lavenderSoft,
    foreground: AppColors.lavender,
  ),
  CanvasTutorialStep.undoRedo: _TutorialContent(
    icon: Icons.undo_rounded,
    title: '되돌리고 다시 그려요',
    description: '위쪽 화살표 버튼으로 방금 그린 선을 되돌리거나 다시 살릴 수 있어요.',
    background: AppColors.leafSoft,
    foreground: AppColors.leaf,
  ),
  CanvasTutorialStep.complete: _TutorialContent(
    icon: Icons.check_circle_rounded,
    title: '그림을 마쳐요',
    description: '그림을 다 그렸다면 완료 버튼을 눌러 다음 이야기로 넘어가요.',
    background: AppColors.successSoft,
    foreground: AppColors.success,
  ),
};
