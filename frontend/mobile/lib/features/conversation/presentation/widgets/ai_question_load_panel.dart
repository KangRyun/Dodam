import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/ai_question_controller.dart';

// 질문 조회 로딩·오류·준비 완료 상태 표시
final class AiQuestionLoadPanel extends StatefulWidget {
  const AiQuestionLoadPanel({required this.controller, super.key});

  final AiQuestionController controller;

  @override
  State<AiQuestionLoadPanel> createState() => _AiQuestionLoadPanelState();
}

final class _AiQuestionLoadPanelState extends State<AiQuestionLoadPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    unawaited(widget.controller.load());
  }

  @override
  void didUpdateWidget(covariant AiQuestionLoadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_refresh);
    widget.controller.addListener(_refresh);
    unawaited(widget.controller.load());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (controller.status) {
        AiQuestionStatus.initial ||
        AiQuestionStatus.loading => const _StatusCard(
          key: ValueKey('ai-question-loading'),
          icon: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.tangerine,
            ),
          ),
          title: '새 질문을 생각하고 있어요',
          description: '그림을 보며 잠시만 기다려 주세요.',
        ),
        AiQuestionStatus.failure => _StatusCard(
          key: const ValueKey('ai-question-error'),
          icon: const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.error,
            size: 32,
          ),
          title: '질문을 불러오지 못했어요',
          description: '잠시 후 다시 한번 불러와 주세요.',
          action: TextButton.icon(
            onPressed: controller.load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('다시 불러오기'),
          ),
        ),
        AiQuestionStatus.success => const _StatusCard(
          key: ValueKey('ai-question-ready'),
          icon: Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.tangerine,
            size: 32,
          ),
          title: '새 질문을 준비했어요!',
          description: '곧 친구가 그림에 관해 물어볼 거예요.',
        ),
      },
    );
  }
}

final class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    super.key,
  });

  final Widget icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.tangerineSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Column(
      children: [
        icon,
        const SizedBox(height: AppSpacing.xs),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        ?action,
      ],
    ),
  );
}
