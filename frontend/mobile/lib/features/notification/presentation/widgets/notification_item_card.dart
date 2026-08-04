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
    final relativeTime = notificationRelativeTime(item.createdAt);
    final semanticsParts = [
      item.isRead ? '읽은 알림' : '읽지 않은 알림',
      item.title,
      if (item.content?.trim() case final content? when content.isNotEmpty)
        content,
      if (relativeTime.isNotEmpty) relativeTime,
    ];

    return Semantics(
      container: true,
      button: true,
      label: semanticsParts.join(', '),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: dense ? AppSizes.minTouchTarget : 72,
            ),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.all(dense ? AppSpacing.sm : AppSpacing.lg),
                child: dense
                    ? _DenseNotificationContent(
                        item: item,
                        visual: visual,
                        iconBox: iconBox,
                        relativeTime: relativeTime,
                      )
                    : _NotificationContent(
                        item: item,
                        visual: visual,
                        iconBox: iconBox,
                        relativeTime: relativeTime,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationContent extends StatelessWidget {
  const _NotificationContent({
    required this.item,
    required this.visual,
    required this.iconBox,
    required this.relativeTime,
  });

  final NotificationItemDto item;
  final _NotificationVisual visual;
  final double iconBox;
  final String relativeTime;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final metadataBelow = constraints.maxWidth < 540 || textScale > 1.35;
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: AppTypography.titleMd.copyWith(
              color: item.isRead ? AppColors.ink : _notificationForest,
              fontWeight: item.isRead ? FontWeight.w700 : FontWeight.w800,
              height: 1.35,
            ),
          ),
          if (item.content?.trim() case final content?
              when content.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              content,
              style: AppTypography.bodySm.copyWith(
                color: item.isRead ? AppColors.inkMuted : AppColors.ink,
                height: 1.45,
              ),
            ),
          ],
          if (metadataBelow && relativeTime.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              relativeTime,
              style: AppTypography.caption.copyWith(
                color: item.isRead ? AppColors.inkMuted : AppColors.ink,
              ),
            ),
          ],
        ],
      );

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NotificationIcon(visual: visual, size: iconBox, iconSize: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: copy),
          if (!metadataBelow) ...[
            const SizedBox(width: AppSpacing.lg),
            Text(
              relativeTime,
              style: AppTypography.caption.copyWith(
                color: item.isRead ? AppColors.inkMuted : AppColors.ink,
              ),
            ),
          ],
          if (!item.isRead) ...[
            const SizedBox(width: AppSpacing.sm),
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: CircleAvatar(
                key: ValueKey('notification-unread-dot'),
                radius: 5,
                backgroundColor: _notificationEmber,
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _DenseNotificationContent extends StatelessWidget {
  const _DenseNotificationContent({
    required this.item,
    required this.visual,
    required this.iconBox,
    required this.relativeTime,
  });

  final NotificationItemDto item;
  final _NotificationVisual visual;
  final double iconBox;
  final String relativeTime;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _NotificationIcon(visual: visual, size: iconBox, iconSize: 22),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: AppTypography.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.content?.trim() case final content?
                when content.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                content,
                style: AppTypography.bodySm.copyWith(
                  color: item.isRead ? AppColors.inkMuted : AppColors.ink,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
            relativeTime,
            style: AppTypography.caption.copyWith(
              color: item.isRead ? AppColors.inkMuted : AppColors.ink,
            ),
          ),
          if (!item.isRead) ...[
            const SizedBox(height: AppSpacing.xs),
            const CircleAvatar(radius: 5, backgroundColor: _notificationEmber),
          ],
        ],
      ),
    ],
  );
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({
    required this.visual,
    required this.size,
    required this.iconSize,
  });

  final _NotificationVisual visual;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: visual.background,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Icon(visual.icon, color: visual.foreground, size: iconSize),
  );
}

const _notificationEmber = Color(0xFFDF8448);
const _notificationForest = Color(0xFF315B49);

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
