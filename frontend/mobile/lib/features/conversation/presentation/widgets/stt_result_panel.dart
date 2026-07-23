import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/stt_result_controller.dart';

final class SttResultPanel extends StatelessWidget {
  const SttResultPanel({required this.controller, super.key});

  final SttResultController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.status == SttResultStatus.idle) {
      return const SizedBox.shrink();
    }
    final (icon, title, message) = switch (controller.status) {
      SttResultStatus.polling => (
        Icons.hearing_rounded,
        '목소리를 글로 바꾸고 있어요',
        '잠시만 기다려 주세요.',
      ),
      SttResultStatus.success => (
        Icons.check_circle_rounded,
        '이렇게 들었어요',
        controller.text ?? '',
      ),
      SttResultStatus.failure => (
        Icons.error_outline_rounded,
        '목소리를 글로 바꾸지 못했어요',
        '녹음한 답변은 안전하게 보관했어요.',
      ),
      SttResultStatus.delayed => (
        Icons.schedule_rounded,
        '변환이 조금 오래 걸리고 있어요',
        '완료되면 활동 기록에서 확인할 수 있어요.',
      ),
      SttResultStatus.idle => throw StateError('idle is hidden'),
    };

    return Material(
      key: const ValueKey('stt-result-panel'),
      elevation: 4,
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, color: AppColors.leaf, size: 30),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      key: controller.status == SttResultStatus.success
                          ? const ValueKey('stt-result-text')
                          : null,
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              if (controller.status != SttResultStatus.polling)
                IconButton(
                  key: const ValueKey('stt-result-dismiss'),
                  onPressed: controller.dismiss,
                  tooltip: '닫기',
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
