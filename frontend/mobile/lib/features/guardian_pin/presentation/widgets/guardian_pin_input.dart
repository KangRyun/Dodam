import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/design_system.dart';

const guardianPinTextFieldKey = ValueKey('guardian-pin-text-field');
const guardianPinDeleteKey = ValueKey('guardian-pin-delete');
const guardianPinClearKey = ValueKey('guardian-pin-clear');

/// 숫자 4자리 PIN을 마스킹해 입력하는 재사용 컴포넌트.
final class GuardianPinInput extends StatelessWidget {
  const GuardianPinInput({
    required this.controller,
    required this.enteredLength,
    required this.enabled,
    required this.onChanged,
    required this.onDelete,
    required this.onClear,
    this.focusNode,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final int enteredLength;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        textField: true,
        enabled: enabled,
        label: '보호자 PIN 입력',
        value: '$enteredLength자리 입력됨',
        child: ExcludeSemantics(
          child: TextField(
            key: guardianPinTextFieldKey,
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            obscureText: true,
            obscuringCharacter: '●',
            enableSuggestions: false,
            autocorrect: false,
            enableInteractiveSelection: false,
            maxLength: 4,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            onChanged: onChanged,
            onSubmitted: (_) => onSubmitted?.call(),
            style: AppTypography.titleLg.copyWith(letterSpacing: AppSpacing.sm),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '● ● ● ●',
              counterText: '',
              filled: true,
              fillColor: enabled ? AppColors.surface : AppColors.surfaceSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.leaf, width: 2),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Semantics(
            button: true,
            enabled: enabled && enteredLength > 0,
            label: 'PIN 한 자리 삭제',
            child: IconButton(
              key: guardianPinDeleteKey,
              tooltip: '한 자리 삭제',
              onPressed: enabled && enteredLength > 0 ? onDelete : null,
              constraints: const BoxConstraints.tightFor(
                width: AppSizes.minTouchTarget,
                height: AppSizes.minTouchTarget,
              ),
              icon: const Icon(Icons.backspace_outlined),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Semantics(
            button: true,
            enabled: enabled && enteredLength > 0,
            label: 'PIN 전체 지우기',
            child: IconButton(
              key: guardianPinClearKey,
              tooltip: '전체 지우기',
              onPressed: enabled && enteredLength > 0 ? onClear : null,
              constraints: const BoxConstraints.tightFor(
                width: AppSizes.minTouchTarget,
                height: AppSizes.minTouchTarget,
              ),
              icon: const Icon(Icons.clear_rounded),
            ),
          ),
        ],
      ),
    ],
  );
}
