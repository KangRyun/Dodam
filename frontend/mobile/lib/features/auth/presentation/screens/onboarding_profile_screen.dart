import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/entities/onboarding_profile_input.dart';
import '../../domain/enums/user_role.dart';

typedef OnboardingProfileSubmit =
    Future<void> Function(OnboardingProfileInput input);

class OnboardingProfileScreen extends StatefulWidget {
  const OnboardingProfileScreen({required this.onSubmit, super.key});

  final OnboardingProfileSubmit onSubmit;

  @override
  State<OnboardingProfileScreen> createState() =>
      _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState extends State<OnboardingProfileScreen> {
  final _nicknameController = TextEditingController();
  UserRole? _selectedRole;
  String? _nicknameError;
  bool _isSubmitting = false;

  bool get _canSubmit =>
      _selectedRole != null &&
      _nicknameController.text.trim().isNotEmpty &&
      !_isSubmitting;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final nickname = _nicknameController.text.trim();
    final role = _selectedRole;
    if (role == null || nickname.isEmpty) {
      setState(() {
        _nicknameError = nickname.isEmpty ? '사용할 닉네임을 입력해 주세요.' : null;
      });
      return;
    }
    if (nickname.length > 50) {
      setState(() => _nicknameError = '닉네임은 50자 이하로 입력해 주세요.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _nicknameError = null;
    });
    try {
      await widget.onSubmit(
        OnboardingProfileInput(role: role, nickname: nickname),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 700;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? AppSpacing.xxl : AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            child: Center(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 640),
                padding: EdgeInsets.all(
                  isTablet ? AppSpacing.xxl : AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ProgressHeader(),
                    const SizedBox(height: AppSpacing.xl),
                    const Text(
                      '도담에서 어떻게 활동할까요?',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      '역할과 기본 정보를 알려주면 꼭 맞는 화면을 준비할게요.',
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const Text(
                      '역할',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _RoleChoices(
                      selectedRole: _selectedRole,
                      onSelected: (role) =>
                          setState(() => _selectedRole = role),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppTextField(
                      key: const ValueKey('onboarding-nickname'),
                      controller: _nicknameController,
                      label: '닉네임',
                      hintText: '도담에서 사용할 이름을 입력해 주세요',
                      helperText: '보호자와 전문가 화면에 표시되는 이름이에요.',
                      errorText: _nicknameError,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() => _nicknameError = null),
                      onSubmitted: (_) => _canSubmit ? _submit() : null,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      key: const ValueKey('onboarding-profile-next'),
                      label: '다음',
                      onPressed: _canSubmit ? _submit : null,
                      isLoading: _isSubmitting,
                      trailing: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.eco_rounded, color: AppColors.leaf),
      SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          '시작하기 1 / 2',
          style: TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _RoleChoices extends StatelessWidget {
  const _RoleChoices({required this.selectedRole, required this.onSelected});

  final UserRole? selectedRole;
  final ValueChanged<UserRole> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stackVertically = constraints.maxWidth < 480;
      final choices = [
        _RoleCard(
          key: const ValueKey('onboarding-role-guardian'),
          role: UserRole.guardian,
          title: '보호자',
          description: '아이의 활동과 관찰 리포트를 확인해요.',
          icon: Icons.family_restroom_rounded,
          selected: selectedRole == UserRole.guardian,
          onTap: onSelected,
        ),
        _RoleCard(
          key: const ValueKey('onboarding-role-expert'),
          role: UserRole.expert,
          title: '전문가',
          description: '아동의 활동 자료를 전문적으로 살펴봐요.',
          icon: Icons.psychology_alt_rounded,
          selected: selectedRole == UserRole.expert,
          onTap: onSelected,
        ),
      ];

      if (stackVertically) {
        return Column(
          children: [
            choices.first,
            const SizedBox(height: AppSpacing.sm),
            choices.last,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: choices.first),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: choices.last),
        ],
      );
    },
  );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final UserRole role;
  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final ValueChanged<UserRole> onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      key: ValueKey('onboarding-role-${role.name}-tap'),
      onTap: () => onTap(role),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minHeight: 148),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.leafSoft : AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.leaf : AppColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: selected ? AppColors.leaf : AppColors.ink),
                const Spacer(),
                if (selected)
                  const Icon(Icons.check_circle_rounded, color: AppColors.leaf),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              description,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
