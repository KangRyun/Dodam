import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/permission_onboarding_controller.dart';

/// 화면 루트 키. 라우터가 이 화면을 세웠는지 테스트가 확인한다.
const permissionOnboardingKey = ValueKey('permission-onboarding');
const permissionOnboardingAllowAllKey = ValueKey('permission-onboarding-allow');
const permissionOnboardingSkipKey = ValueKey('permission-onboarding-skip');

/// 응답이 끝나 다음 화면으로 넘어갈 때 라우터가 하는 일.
typedef PermissionOnboardingFinished = void Function(BuildContext context);

/// 로그인 직후 한 번만 보여주는 권한 안내(보호자 대상).
///
/// 마이크·카메라·알림을 "모두 허용"으로 한 번에 묻거나 "나중에"로 건너뛴다. 어느
/// 쪽을 골라도 응답으로 기록돼 다시 뜨지 않고, 건너뛴 권한은 실제로 필요한 순간에
/// 기존 개별 요청이 다시 묻는다 — 이 화면은 앞당겨 묻는 장치일 뿐 대체가 아니다.
///
/// ⚠️ 카피 원칙(CLAUDE.md 9절): **권한은 기기 접근이고 동의는 데이터 처리 근거다.**
/// 둘을 섞어 읽히면 보호자가 "여기서 허용 = 아이 데이터 제공 동의"로 오해한다.
/// 그래서 각 항목은 *언제 켜지는지*까지 적고, 아래 안내로 동의 체계를 따로 가리킨다.
class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({
    required this.controller,
    required this.onFinished,
    super.key,
  });

  final PermissionOnboardingController controller;
  final PermissionOnboardingFinished onFinished;

  @override
  State<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState
    extends State<PermissionOnboardingScreen> {
  /// 권한 요청이 진행 중인지. 시스템 대화상자가 순서대로 뜨는 동안 두 번째 탭이
  /// 같은 요청을 다시 시작하지 못하게 막는다.
  bool _isWorking = false;

  Future<void> _finishWith(Future<void> Function() respond) async {
    if (_isWorking) return;
    setState(() => _isWorking = true);
    await respond();
    if (!mounted) return;
    // 응답은 이미 기록됐다. 요청이 실패했더라도 여기서 멈추지 않는다.
    widget.onFinished(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: permissionOnboardingKey,
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: ResponsiveContent(
        maxWidth: AppSizes.contentMaxWidth,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 가로 고정 화면(S15P11B209-878)이라 세로 공간이 좁다. 본문은 스크롤로
            // 두고 버튼만 아래에 붙여 둔다.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    const Text('시작하기 전에 잠깐요', style: AppTypography.titleLg),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      '아이와 그림을 그리고 이야기 나누려면 기기의 세 가지 기능이 필요해요.\n'
                      '지금 한 번에 허용해 두면 활동 중에 흐름이 끊기지 않아요.',
                      style: AppTypography.bodySm,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _PermissionItem(
                      icon: Icons.mic_rounded,
                      title: '마이크',
                      purpose: '아이가 그림 이야기를 말로 들려줄 수 있어요.',
                      whenUsed: '아이가 말하기 버튼을 누른 동안에만 켜져요.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _PermissionItem(
                      icon: Icons.photo_camera_rounded,
                      title: '카메라',
                      purpose: '종이에 그린 그림을 찍어서 올릴 수 있어요.',
                      whenUsed: '사진을 찍는 화면에서만 켜져요.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _PermissionItem(
                      icon: Icons.notifications_rounded,
                      title: '알림',
                      purpose: '관찰 리포트가 준비되면 보호자에게 알려드려요.',
                      whenUsed: '아이 화면에는 알림이 뜨지 않아요.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _ConsentDistinctionNote(),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
            AppButton(
              key: permissionOnboardingAllowAllKey,
              label: '모두 허용하기',
              isLoading: _isWorking,
              onPressed: () => _finishWith(widget.controller.requestAll),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              key: permissionOnboardingSkipKey,
              label: '나중에 할게요',
              variant: AppButtonVariant.secondary,
              onPressed: _isWorking
                  ? null
                  : () => _finishWith(widget.controller.skip),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              '나중에 허용해도 괜찮아요 — 필요한 순간에 다시 여쭤볼게요.',
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    ),
  );
}

class _PermissionItem extends StatelessWidget {
  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.purpose,
    required this.whenUsed,
  });

  final IconData icon;
  final String title;

  /// 이 서비스에서 무엇에 쓰이는지.
  final String purpose;

  /// 언제 켜지는지. "늘 켜져 있다"는 오해를 막는 문장이라 항목마다 반드시 둔다.
  final String whenUsed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.outline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: AppColors.leafSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.leaf, size: AppIconSize.lg),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.bodyStrong),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                purpose,
                style: AppTypography.bodySm.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(whenUsed, style: AppTypography.caption),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 권한(기기 접근)과 동의(데이터 처리 근거)를 갈라 주는 안내.
///
/// 이 화면에서 "모두 허용"을 누른 보호자가 아이 데이터 제공에까지 동의했다고
/// 여기면 안 된다(CLAUDE.md 9절). 동의는 가입 때 받고 설정에서 언제든 바꾼다.
class _ConsentDistinctionNote extends StatelessWidget {
  const _ConsentDistinctionNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: AppIconSize.md,
          color: AppColors.inkMuted,
        ),
        const SizedBox(width: AppSpacing.xs),
        const Expanded(
          child: Text(
            '허용은 기기 기능을 여는 것이에요. 아이 정보를 어떻게 다룰지는 가입할 때 받은 '
            '동의로 정해지고, 설정 > 동의 관리에서 언제든 다시 보고 바꿀 수 있어요.',
            style: AppTypography.caption,
          ),
        ),
      ],
    ),
  );
}
