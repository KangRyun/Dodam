import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../design_system/design_system.dart';
import '../../../child/data/dto/child_dtos.dart';

class ChildModeHomeScreen extends StatelessWidget {
  const ChildModeHomeScreen({required this.child, super.key});

  final ChildSummaryDto child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      backgroundColor: AppColors.childCanvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: '길게 눌러 보호자 화면으로 돌아가기',
                  child: GestureDetector(
                    key: const ValueKey('guardian-return-hold'),
                    onLongPress: () => AppRouter.goGuardianHome(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            color: AppColors.inkMuted,
                            size: 20,
                          ),
                          SizedBox(width: AppSpacing.xs),
                          Text(
                            '보호자 화면',
                            style: TextStyle(
                              color: AppColors.inkMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSizes.wideContentMaxWidth,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 132,
                            height: 132,
                            decoration: const BoxDecoration(
                              color: AppColors.tangerineSoft,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.emoji_nature_rounded,
                              size: 72,
                              color: AppColors.tangerine,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            '${child.nickname}, 오늘은 무엇을 그려 볼까?',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(
                            '그리고 싶은 것을 천천히 골라도 괜찮아!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final draw = _ChildActionCard(
                                key: const ValueKey('draw-action'),
                                icon: Icons.palette_rounded,
                                title: '그림 그리기',
                                description: '새로운 그림을 시작해 보자',
                                color: AppColors.tangerine,
                                onTap: () => Navigator.of(context).pushNamed(
                                  AppRoutes.drawing(child.childId.toString()),
                                ),
                              );
                              const history = _ChildActionCard(
                                icon: Icons.collections_bookmark_outlined,
                                title: '지난 그림 보기',
                                description: '다음 단계에서 만날 수 있어요',
                                color: AppColors.lavender,
                              );
                              if (constraints.maxWidth < 700) {
                                return Column(
                                  children: [
                                    history,
                                    const SizedBox(height: AppSpacing.md),
                                    draw,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  const Expanded(child: history),
                                  const SizedBox(width: AppSpacing.lg),
                                  Expanded(child: draw),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ChildActionCard extends StatelessWidget {
  const _ChildActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    this.onTap,
    super.key,
  });
  final IconData icon;
  final String title, description;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    enabled: onTap != null,
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 180),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 58,
                  color: onTap == null ? AppColors.disabled : color,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
