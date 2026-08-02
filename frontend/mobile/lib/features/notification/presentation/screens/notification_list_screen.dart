import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/notification_badge_controller.dart';
import '../../data/dto/notification_inbox_dtos.dart';
import '../../domain/repositories/notification_inbox_repository.dart';

/// 서버 알림함을 최신순으로 보여주는 보호자 알림 탭.
///
/// 첫 페이지와 추가 페이지 모두 NOTI-03을 사용하며 화면 내부에 샘플 알림을
/// 만들지 않는다. 서버가 빈 목록을 반환하면 빈 상태를 표시한다.
class NotificationListScreen extends StatefulWidget {
  const NotificationListScreen({
    required this.repository,
    this.badgeController,
    super.key,
  });

  final NotificationInboxRepository repository;

  /// 읽음 처리 결과를 사이드바 배지에 반영할 대상. 주지 않으면 배지를 갱신하지
  /// 않고 목록만 동작한다(단독 라우트·테스트 구성).
  final NotificationBadgeController? badgeController;

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
  final _scrollController = ScrollController();
  final List<NotificationItemDto> _items = [];

  /// 읽음 처리 응답을 기다리는 중인 알림 id. 카드가 들고 있는 [NotificationItemDto]는
  /// build 시점에 캡처된 불변 인스턴스라 응답이 오기 전에는 계속 미열람으로 보인다.
  /// 연타를 막지 않으면 서버는 멱등이라 1건만 줄지만 배지는 두 번 줄어든다.
  final _pendingReads = <int>{};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isMarkingAllRead = false;
  bool _hasNext = false;
  Object? _error;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearBottom);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreNearBottom)
      ..dispose();
    super.dispose();
  }

  void _loadMoreNearBottom() {
    if (_scrollController.position.extentAfter < 320) _loadMore();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await widget.repository.getNotifications();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.content);
        _page = result.page;
        _hasNext = result.hasNext;
      });
      // 사이드바 셸이 IndexedStack으로 탭을 살려 두므로 알림 탭에 다시 들어와도
      // initState가 재실행되지 않는다. 당겨서 새로고침·오류 재시도처럼 사용자가
      // 목록을 다시 받는 지점이 배지 어긋남을 되돌릴 창구가 된다. 목록 왕복과
      // 함께 보내고 기다리지 않아 새로고침 표시가 길어지지 않는다.
      unawaited(widget.badgeController?.refresh());
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasNext) return;
    setState(() => _isLoadingMore = true);

    try {
      final result = await widget.repository.getNotifications(
        filter: NotificationFilterDto(page: _page + 1),
      );
      if (!mounted) return;
      setState(() {
        final knownIds = _items.map((item) => item.notificationId).toSet();
        _items.addAll(
          result.content.where(
            (item) => !knownIds.contains(item.notificationId),
          ),
        );
        _page = result.page;
        _hasNext = result.hasNext;
      });
    } on Object {
      if (mounted) {
        showAppMessage(
          context,
          message: '알림을 더 불러오지 못했어요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _markRead(NotificationItemDto item) async {
    if (item.isRead) return;
    // 응답을 기다리는 동안 같은 카드를 다시 눌러도 위 isRead 가드는 통과한다.
    // 진행 중인 id를 붙잡아 두 번째 탭을 흘려보내야 감산이 한 번만 일어난다.
    if (!_pendingReads.add(item.notificationId)) return;

    try {
      final result = await widget.repository.markRead(item.notificationId);
      // 화면에 미열람으로 남아 있던 항목의 첫 읽음 처리이므로 배지에서 1건 뺀다.
      // (다른 기기에서 이미 읽은 건이면 서버 미열람 수는 그대로라 배지가 한 건
      // 적게 표시될 수 있다 — 응답에 판별 필드가 없어 다음 갱신 때 복구된다.)
      widget.badgeController?.decrementBy(1);
      if (!mounted) return;
      final index = _items.indexWhere(
        (candidate) => candidate.notificationId == item.notificationId,
      );
      if (index < 0) return;
      setState(() {
        _items[index] = _copyWithReadAt(_items[index], result.readAt);
      });
    } on Object {
      if (mounted) {
        showAppMessage(
          context,
          message: '알림을 읽음 처리하지 못했어요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      _pendingReads.remove(item.notificationId);
    }
  }

  Future<void> _markAllRead() async {
    if (_isMarkingAllRead || !_items.any((item) => !item.isRead)) return;
    setState(() => _isMarkingAllRead = true);

    try {
      final result = await widget.repository.markAllRead();
      // updatedCount는 이번 호출로 새로 읽음 처리된 건수다(계약 §6.5). 화면에
      // 안 올라온 페이지의 미열람까지 포함하므로 목록 길이 대신 이 값을 쓴다.
      widget.badgeController?.decrementBy(result.updatedCount);
      if (!mounted) return;
      final readAt = result.readAt ?? DateTime.now().toIso8601String();
      setState(() {
        for (var index = 0; index < _items.length; index++) {
          final item = _items[index];
          if (!item.isRead) _items[index] = _copyWithReadAt(item, readAt);
        }
      });
    } on Object {
      if (mounted) {
        showAppMessage(
          context,
          message: '전체 읽음 처리에 실패했어요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isMarkingAllRead = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '알림',
      actions: [
        TextButton(
          key: const ValueKey('mark-all-read'),
          onPressed:
              _isLoading ||
                  _isMarkingAllRead ||
                  !_items.any((item) => !item.isRead)
              ? null
              : _markAllRead,
          child: _isMarkingAllRead
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('모두 읽음'),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    ),
    body: SafeArea(child: _buildBody()),
  );

  Widget _buildBody() {
    if (_isLoading) {
      return const AppLoadingView(message: '알림을 불러오고 있어요');
    }
    if (_error != null && _items.isEmpty) {
      return AppRetryView(
        title: '알림을 불러오지 못했어요',
        message: '인터넷 연결을 확인하고 다시 시도해 주세요.',
        onRetry: _loadFirstPage,
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            AppEmptyView(
              title: '아직 알림이 없어요',
              message: '분석이나 리포트 소식이 생기면 이곳에서 알려드릴게요.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.xl),
        itemCount: _items.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = _items[index];
          return _NotificationCard(item: item, onTap: () => _markRead(item));
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final NotificationItemDto item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(item.type);
    return Material(
      color: item.isRead ? AppColors.surface : AppColors.leafSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: item.isRead ? AppColors.outline : AppColors.leaf,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(visual.icon, color: visual.foreground, size: 28),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: AppTypography.titleMd),
                    if (item.content case final content?)
                      if (content.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(content, style: AppTypography.bodySm),
                      ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _relativeTime(item.createdAt),
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

String _relativeTime(String value) {
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

NotificationItemDto _copyWithReadAt(NotificationItemDto item, String readAt) =>
    NotificationItemDto(
      notificationId: item.notificationId,
      type: item.type,
      title: item.title,
      content: item.content,
      relatedResourceType: item.relatedResourceType,
      relatedResourceId: item.relatedResourceId,
      data: item.data,
      deliveryStatus: item.deliveryStatus,
      readAt: readAt,
      sentAt: item.sentAt,
      createdAt: item.createdAt,
    );
