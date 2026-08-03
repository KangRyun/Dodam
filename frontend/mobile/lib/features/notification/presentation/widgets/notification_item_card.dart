import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../data/dto/notification_inbox_dtos.dart';

/// 알림 한 건을 그리는 카드.
///
/// 알림함 목록 화면과 보호자 대시보드 알림 팝업이 같은 카드를 쓴다. 유형별
/// 아이콘·미열람 표시·상대 시각이 두 곳에서 갈라지면 같은 알림이 화면에 따라
/// 다르게 보인다.
class NotificationItemCard extends StatelessWidget {
  const NotificationItemCard({
    required this.item,
    required this.onTap,
    this.dense = false,
    super.key,
  });

  final NotificationItemDto item;
  final VoidCallback onTap;

  /// 팝업처럼 좁은 자리에서 쓰는 축약 배치. 아이콘과 여백을 줄이고 본문을
  /// 두 줄로 자른다.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(item.type);
    final iconBox = dense ? 40.0 : 52.0;
    return Material(
      color: item.isRead ? AppColors.surface : AppColors.leafSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          dense ? AppRadius.md : AppRadius.lg,
        ),
        side: BorderSide(
          color: item.isRead ? AppColors.outline : AppColors.leaf,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(dense ? AppSpacing.sm : AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  visual.icon,
                  color: visual.foreground,
                  size: dense ? 22 : 28,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: dense
                          ? AppTypography.bodyStrong
                          : AppTypography.titleMd,
                      maxLines: dense ? 1 : null,
                      overflow: dense ? TextOverflow.ellipsis : null,
                    ),
                    if (item.content case final content?)
                      if (content.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          content,
                          style: AppTypography.bodySm,
                          maxLines: dense ? 2 : null,
                          overflow: dense ? TextOverflow.ellipsis : null,
                        ),
                      ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    notificationRelativeTime(item.createdAt),
                    style: AppTypography.caption,
                  ),
                  if (!item.isRead) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Semantics(
                      label: '읽지 않은 알림',
                      child: const CircleAvatar(
                        radius: 5,
                        backgroundColor: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 알림 생성 시각을 상대 표기로 바꾼다. 파싱하지 못하면 빈 문자열이다.
///
/// 알림함과 팝업이 같은 알림에 같은 문구를 보여야 하므로 함수를 공유한다.
String notificationRelativeTime(String value) {
  final createdAt = DateTime.tryParse(value)?.toLocal();
  if (createdAt == null) return '';
  final now = DateTime.now();
  final difference = now.difference(createdAt);

  if (difference.isNegative || difference.inMinutes < 1) return '방금';
  if (difference.inHours < 1) return '${difference.inMinutes}분 전';
  if (difference.inDays < 1) return '${difference.inHours}시간 전';
  if (difference.inDays == 1) return '어제';
  if (difference.inDays < 7) return '${difference.inDays}일 전';
  return '${createdAt.month}/${createdAt.day}';
}

class _NotificationVisual {
  const _NotificationVisual(this.icon, this.foreground, this.background);

  final IconData icon;
  final Color foreground;
  final Color background;
}

_NotificationVisual _visualFor(String type) => switch (type) {
  'ANALYSIS_COMPLETED' || 'REPORT_COMPLETED' => const _NotificationVisual(
    Icons.check_circle_outline_rounded,
    AppColors.success,
    AppColors.successSoft,
  ),
  'ANALYSIS_FAILED' => const _NotificationVisual(
    Icons.warning_amber_rounded,
    AppColors.error,
    AppColors.errorSoft,
  ),
  'NEW_EXPERT_POST' || 'COMMENT_CREATED' => const _NotificationVisual(
    Icons.chat_bubble_outline_rounded,
    AppColors.lavender,
    AppColors.lavenderSoft,
  ),
  'CONSENT_UPDATED' => const _NotificationVisual(
    Icons.description_outlined,
    AppColors.drawingBlue,
    Color(0xFFEAF1FC),
  ),
  'RETENTION_NOTICE' => const _NotificationVisual(
    Icons.hourglass_bottom_rounded,
    AppColors.warning,
    AppColors.warningSoft,
  ),
  'ACTIVITY_REMINDER' => const _NotificationVisual(
    Icons.brush_outlined,
    AppColors.tangerine,
    AppColors.tangerineSoft,
  ),
  'RISK_REVIEW_GUIDE' => const _NotificationVisual(
    Icons.shield_outlined,
    AppColors.warning,
    AppColors.warningSoft,
  ),
  _ => const _NotificationVisual(
    Icons.notifications_none_rounded,
    AppColors.leaf,
    AppColors.leafSoft,
  ),
};
