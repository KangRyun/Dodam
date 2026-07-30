import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/network/network.dart';
import '../../../../design_system/design_system.dart';
import '../../application/ai_question_controller.dart';

// 질문 조회 로딩·오류·준비 완료 상태 표시
final class AiQuestionLoadPanel extends StatefulWidget {
  const AiQuestionLoadPanel({
    required this.controller,
    this.loadOnMount = true,
    super.key,
  });

  final AiQuestionController controller;
  final bool loadOnMount;

  @override
  State<AiQuestionLoadPanel> createState() => _AiQuestionLoadPanelState();
}

final class _AiQuestionLoadPanelState extends State<AiQuestionLoadPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    if (widget.loadOnMount) unawaited(widget.controller.load());
  }

  @override
  void didUpdateWidget(covariant AiQuestionLoadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_refresh);
    widget.controller.addListener(_refresh);
    if (widget.loadOnMount) unawaited(widget.controller.load());
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
        AiQuestionStatus.initial when !widget.loadOnMount => const _StatusCard(
          key: ValueKey('ai-question-waiting-for-drawing'),
          icon: Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.tangerine,
            size: 32,
          ),
          title: '그림을 자유롭게 그려 보세요',
          description: '그림을 보고 도다미가 궁금한 것을 물어볼 거예요.',
        ),
        AiQuestionStatus.initial || AiQuestionStatus.loading => _StatusCard(
          key: const ValueKey('ai-question-loading'),
          // 대기 시작만 한 번 읽어주고 progress 애니메이션은 낭독하지 않는다.
          liveMessage: '새 질문을 생각하고 있어요. 잠시만 기다려 주세요.',
          icon: const ExcludeSemantics(
            child: SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.tangerine,
              ),
            ),
          ),
          title: '새 질문을 생각하고 있어요',
          description: '그림을 보며 잠시만 기다려 주세요.',
        ),
        AiQuestionStatus.failure => _StatusCard(
          key: const ValueKey('ai-question-error'),
          liveMessage: _failureLiveMessage(controller.error),
          icon: const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.error,
            size: 32,
          ),
          title: '질문을 불러오지 못했어요',
          description: _failureDescription(controller.error),
          // 같은 요청을 반복해도 결과가 같은 실패(401·403·404·검증 오류)에는
          // 재시도 버튼을 만들지 않는다 — 공통 AppFailureView와 같은 기준이다.
          action: controller.canRetry
              ? TextButton(
                  key: const ValueKey('ai-question-retry'),
                  onPressed: controller.load,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded),
                      SizedBox(width: AppSpacing.xs),
                      // 큰 글자 배율에서 줄바꿈으로 흘려보내 overflow를 막는다.
                      Flexible(child: Text('다시 불러오기')),
                    ],
                  ),
                )
              : null,
        ),
        // 성공 질문은 말풍선에서, 정상 대화 종료는 다음 화면에서 표시
        AiQuestionStatus.success || AiQuestionStatus.conversationComplete =>
          const SizedBox.shrink(key: ValueKey('ai-question-ready')),
      },
    );
  }

  /// 아이 화면에는 원인을 드러내지 않는 두 가지 문구만 쓴다(가드레일 9절).
  static String _failureDescription(Object? error) =>
      ApiFailurePresentation.of(error, childFriendly: true).message;

  static String _failureLiveMessage(Object? error) =>
      '질문을 불러오지 못했어요. ${_failureDescription(error)}';
}

final class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.liveMessage,
    super.key,
  });

  final Widget icon;
  final String title;
  final String description;
  final Widget? action;

  /// 상태가 바뀐 순간 스크린리더가 한 번 읽어줄 문구.
  ///
  /// 아이콘·색만으로 상태를 구분하지 않도록 문구를 항상 함께 제공한다. 값이
  /// 없으면 live region을 만들지 않아 정적 안내 카드가 반복 낭독되지 않는다.
  final String? liveMessage;

  @override
  Widget build(BuildContext context) {
    final message = Column(
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
      ],
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.tangerineSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          // 안내 문구만 live region으로 묶는다. 재시도 버튼은 바깥에 두어야
          // 초점을 받을 수 있고, 안쪽 Text를 배제해야 같은 말을 두 번 읽지 않는다.
          if (liveMessage case final live?)
            Semantics(
              liveRegion: true,
              container: true,
              label: live,
              child: ExcludeSemantics(child: message),
            )
          else
            message,
          ?action,
        ],
      ),
    );
  }
}
