import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/guardian_pin_controller.dart';
import 'guardian_pin_input.dart';

const guardianPinSubmitKey = ValueKey('guardian-pin-submit');
const guardianPinMessageKey = ValueKey('guardian-pin-message');

/// Route와 독립적으로 주입해 쓰는 보호자 PIN presentation panel.
///
/// production navigation/DI에는 등록하지 않는다. 성공 시 선택적으로 callback만
/// 알리며 화면 전환 정책은 호출자가 별도 이슈에서 결정한다.
final class GuardianPinPanel extends StatefulWidget {
  const GuardianPinPanel({
    required this.controller,
    this.onCompleted,
    super.key,
  });

  final GuardianPinController controller;
  final VoidCallback? onCompleted;

  @override
  State<GuardianPinPanel> createState() => _GuardianPinPanelState();
}

final class _GuardianPinPanelState extends State<GuardianPinPanel> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode(debugLabel: 'guardian-pin-input');
  int _inputRevision = 0;
  int _completionRevision = 0;

  @override
  void initState() {
    super.initState();
    _bind(widget.controller);
  }

  @override
  void didUpdateWidget(covariant GuardianPinPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    _bind(widget.controller);
  }

  void _bind(GuardianPinController controller) {
    _inputRevision = controller.inputRevision;
    _completionRevision = controller.completionRevision;
    _textController.clear();
    controller.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final controller = widget.controller;
    if (_inputRevision != controller.inputRevision) {
      _inputRevision = controller.inputRevision;
      _textController.clear();
    }
    if (_completionRevision != controller.completionRevision) {
      _completionRevision = controller.completionRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCompleted?.call();
      });
    }
    setState(() {});
  }

  void _deleteDigit() {
    final value = _textController.text;
    if (value.isEmpty) return;
    final next = value.substring(0, value.length - 1);
    _textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    widget.controller.updateInput(next);
  }

  void _clearInput() {
    _textController.clear();
    widget.controller.clearInput();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _textController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ColoredBox(
      color: AppColors.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minHeight = constraints.hasBoundedHeight
              ? (constraints.maxHeight - AppSpacing.xl * 2).clamp(
                  0.0,
                  double.infinity,
                )
              : 0.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          controller.title,
                          textAlign: TextAlign.center,
                          style: AppTypography.titleLg,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          controller.instruction,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(
                            color: AppColors.inkMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: GuardianPinInput(
                            controller: _textController,
                            focusNode: _pinFocusNode,
                            enteredLength: controller.inputLength,
                            enabled: controller.canEdit,
                            onChanged: controller.updateInput,
                            onDelete: _deleteDigit,
                            onClear: _clearInput,
                            onSubmitted: controller.canSubmit
                                ? controller.submit
                                : null,
                          ),
                        ),
                        if (controller.message case final message?) ...[
                          const SizedBox(height: AppSpacing.md),
                          Semantics(
                            key: guardianPinMessageKey,
                            liveRegion: true,
                            label: message,
                            child: ExcludeSemantics(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: controller.isLocked
                                      ? AppColors.warningSoft
                                      : controller.isCompleted
                                      ? AppColors.successSoft
                                      : AppColors.errorSoft,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        controller.isLocked
                                            ? Icons.lock_clock_outlined
                                            : controller.isCompleted
                                            ? Icons.check_circle_outline
                                            : Icons.info_outline,
                                        color: controller.isLocked
                                            ? AppColors.warning
                                            : controller.isCompleted
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: Text(
                                          message,
                                          style: AppTypography.bodySm.copyWith(
                                            color: AppColors.ink,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: AppButton(
                            key: guardianPinSubmitKey,
                            label: controller.isLocked
                                ? '상태 다시 확인'
                                : controller.submitLabel,
                            isLoading: controller.isSubmitting,
                            onPressed:
                                controller.isSubmitting ||
                                    controller.isCompleted
                                ? null
                                : controller.isLocked
                                ? controller.refreshStatus
                                : controller.canSubmit
                                ? controller.submit
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
