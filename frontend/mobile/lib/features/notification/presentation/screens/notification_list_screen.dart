import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/notification_route_resolver.dart';
import '../../../../design_system/design_system.dart';
import '../../application/notification_badge_controller.dart';
import '../../application/notification_read_marker.dart';
import '../../data/dto/notification_inbox_dtos.dart';
import '../../domain/repositories/notification_inbox_repository.dart';
import '../widgets/notification_item_card.dart';

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

  /// 읽음 처리와 배지 동기화. 대시보드 알림 팝업이 같은 것을 쓴다.
  late final NotificationReadMarker _readMarker = NotificationReadMarker(
    widget.repository,
    badgeController: widget.badgeController,
  );

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isMarkingAllRead = false;
  bool _hasNext = false;
  Object? _error;
  int _page = 0;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearBottom);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _scrollController
      ..removeListener(_loadMoreNearBottom)
      ..dispose();
    super.dispose();
  }

  void _loadMoreNearBottom() {
    if (_scrollController.position.extentAfter < 320) _loadMore();
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _error = null;
    });

    try {
      final result = await widget.repository.getNotifications();
      if (!mounted || generation != _loadGeneration) return;
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
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasNext) return;
    final generation = _loadGeneration;
    setState(() => _isLoadingMore = true);

    try {
      final result = await widget.repository.getNotifications(
        filter: NotificationFilterDto(page: _page + 1),
      );
      if (!mounted || generation != _loadGeneration) return;
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
      if (mounted && generation == _loadGeneration) {
        showAppMessage(
          context,
          message: '알림을 더 불러오지 못했어요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  /// 알림 카드를 눌렀을 때 읽음 처리와 화면 이동을 함께 수행한다.
  ///
  /// 읽음 처리(NOTI-04)는 멱등하고 이동과 독립이라 결과를 기다리지 않는다.
  /// 푸시 클릭 경로에는 읽음 호출 자체가 없으므로, 여기서 읽음을 이동의 전제로
  /// 삼으면 두 경로의 동작이 갈라진다. 실패하면 `_markRead`가 안내만 띄운다.
  ///
  /// 이동 대상은 푸시와 같은 매핑 함수가 정한다(S15P11B209-501, 푸시 계약 §4.3).
  /// 연결 자원이 없으면 계약상 알림함 목록이 기본값인데 이미 그 화면이므로
  /// 이동하지 않는다.
  void _handleCardTap(NotificationItemDto item) {
    unawaited(_markRead(item));

    final route = resolveNotificationItemRoute(
      relatedResourceType: item.relatedResourceType,
      relatedResourceId: item.relatedResourceId,
    );
    if (route == null) return;

    AppNavigation.pushNamed(context, route);
  }

  Future<void> _markRead(NotificationItemDto item) async {
    final result = await _readMarker.markRead(item);
    if (!mounted) return;
    if (result.outcome == NotificationReadOutcome.failure) {
      showAppMessage(
        context,
        message: '알림을 읽음 처리하지 못했어요.',
        type: AppMessageType.error,
      );
      return;
    }
    final readAt = result.readAt;
    if (readAt == null) return;
    final index = _items.indexWhere(
      (candidate) => candidate.notificationId == item.notificationId,
    );
    if (index < 0) return;
    setState(() => _items[index] = _items[index].copyWithReadAt(readAt));
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
          if (!item.isRead) _items[index] = item.copyWithReadAt(readAt);
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
    appBar: const AppTopBar(title: '알림'),
    body: SafeArea(child: _buildBody()),
  );

  Widget _buildBody() => LayoutBuilder(
    builder: (context, constraints) {
      final contentWidth = constraints.maxWidth
          .clamp(0.0, AppSizes.wideContentMaxWidth)
          .toDouble();
      final horizontalPadding = switch (contentWidth) {
        < 480 => AppSpacing.md,
        < 900 => AppSpacing.lg,
        _ => AppSpacing.xl,
      };

      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: contentWidth,
          height: constraints.maxHeight,
          child: RefreshIndicator(
            onRefresh: _loadFirstPage,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.lg,
                    horizontalPadding,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _NotificationHeraldBanner(
                      badgeController: widget.badgeController,
                      canMarkAllRead:
                          !_isLoading &&
                          !_isMarkingAllRead &&
                          _items.any((item) => !item.isRead),
                      isMarkingAllRead: _isMarkingAllRead,
                      onMarkAllRead: _markAllRead,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.lg),
                ),
                ..._buildContentSlivers(horizontalPadding),
              ],
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _buildContentSlivers(double horizontalPadding) {
    if (_isLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppLoadingView(message: '알림을 불러오고 있어요'),
        ),
      ];
    }
    if (_error != null && _items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppRetryView(
            title: '알림을 불러오지 못했어요',
            message: '인터넷 연결을 확인하고 다시 시도해 주세요.',
            onRetry: _loadFirstPage,
          ),
        ),
      ];
    }
    if (_items.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppEmptyView(
            title: '새로운 알림이 없어요',
            message: '새 소식이 도착하면 이곳에서 알려드릴게요.',
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          AppSpacing.xl,
        ),
        sliver: SliverList.builder(
          itemCount: _items.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _items.length) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final item = _items[index];
            return _NotificationTimelineEntry(
              item: item,
              isFirst: index == 0,
              isLast: index == _items.length - 1,
              onTap: () => _handleCardTap(item),
            );
          },
        ),
      ),
    ];
  }
}

abstract final class _HeraldPalette {
  static const sage = Color(0xFFDDEAD5);
  static const sageSoft = Color(0xFFEEF5E9);
  static const forest = Color(0xFF315B49);
  static const parchment = Color(0xFFF7EAC8);
  static const parchmentSoft = Color(0xFFFFF8E8);
  static const outline = Color(0xFFE7D9B8);
  static const brass = Color(0xFFC89B3C);
  static const walnut = Color(0xFF795035);
  static const ink = Color(0xFF2F3531);
}

class _NotificationHeraldBanner extends StatelessWidget {
  const _NotificationHeraldBanner({
    required this.badgeController,
    required this.canMarkAllRead,
    required this.isMarkingAllRead,
    required this.onMarkAllRead,
  });

  final NotificationBadgeController? badgeController;
  final bool canMarkAllRead;
  final bool isMarkingAllRead;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 720;
      final frameSize = switch (constraints.maxWidth) {
        < 420 => 104.0,
        < 720 => 116.0,
        < 1000 => 148.0,
        _ => 164.0,
      };
      final character = _TrumpeterFrame(size: frameSize);
      final copy = _HeraldCopy(compact: compact);
      final actions = _HeraldActions(
        badgeController: badgeController,
        canMarkAllRead: canMarkAllRead,
        isMarkingAllRead: isMarkingAllRead,
        onMarkAllRead: onMarkAllRead,
      );

      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: '알림 안내',
        child: Container(
          key: const ValueKey('notification-herald-banner'),
          decoration: BoxDecoration(
            color: _HeraldPalette.sage,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: _HeraldPalette.outline),
            boxShadow: [
              BoxShadow(
                color: _HeraldPalette.walnut.withValues(alpha: 0.09),
                offset: const Offset(0, 5),
                blurRadius: 12,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg - 1),
            child: Stack(
              children: [
                const Positioned.fill(child: _HeraldDecoration()),
                Padding(
                  padding: EdgeInsets.all(
                    compact ? AppSpacing.lg : AppSpacing.xl,
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                character,
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(child: copy),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            actions,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            character,
                            const SizedBox(width: AppSpacing.xl),
                            Expanded(child: copy),
                            const SizedBox(width: AppSpacing.xl),
                            Flexible(child: actions),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _HeraldCopy extends StatelessWidget {
  const _HeraldCopy({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: _HeraldPalette.sageSoft,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: _HeraldPalette.outline),
        ),
        child: Text(
          '도담이 소식함',
          style: AppTypography.label.copyWith(
            color: _HeraldPalette.forest,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
      Semantics(
        header: true,
        child: Text(
          '새로운 소식이 도착했어요',
          style: AppTypography.titleLg.copyWith(
            color: _HeraldPalette.forest,
            height: 1.25,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        '활동과 리포트에 관한 알림을 확인할 수 있어요.',
        style: AppTypography.body.copyWith(
          color: _HeraldPalette.ink,
          height: 1.45,
        ),
      ),
    ],
  );
}

class _HeraldActions extends StatelessWidget {
  const _HeraldActions({
    required this.badgeController,
    required this.canMarkAllRead,
    required this.isMarkingAllRead,
    required this.onMarkAllRead,
  });

  final NotificationBadgeController? badgeController;
  final bool canMarkAllRead;
  final bool isMarkingAllRead;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      if (badgeController case final NotificationBadgeController controller)
        ValueListenableBuilder<int>(
          valueListenable: controller,
          builder: (context, unreadCount, _) => Semantics(
            label: unreadCount == 0 ? '읽지 않은 알림 없음' : '읽지 않은 알림 $unreadCount건',
            child: ExcludeSemantics(
              child: Container(
                key: const ValueKey('notification-unread-count'),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: _HeraldPalette.parchmentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: _HeraldPalette.brass),
                ),
                child: Text(
                  unreadCount == 0 ? '새 알림 없음' : '읽지 않음 $unreadCount건',
                  style: AppTypography.bodyStrong.copyWith(
                    color: _HeraldPalette.forest,
                  ),
                ),
              ),
            ),
          ),
        ),
      Semantics(
        label: isMarkingAllRead ? '모두 읽음 처리 중' : '모두 읽음',
        button: true,
        enabled: canMarkAllRead,
        child: ExcludeSemantics(
          child: OutlinedButton.icon(
            key: const ValueKey('mark-all-read'),
            onPressed: canMarkAllRead ? onMarkAllRead : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSizes.minTouchTarget),
              foregroundColor: _HeraldPalette.forest,
              backgroundColor: _HeraldPalette.parchmentSoft,
              disabledForegroundColor: AppColors.onDisabled,
              side: const BorderSide(color: _HeraldPalette.brass),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            icon: isMarkingAllRead
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done_all_rounded),
            label: Text(isMarkingAllRead ? '처리 중' : '모두 읽음'),
          ),
        ),
      ),
    ],
  );
}

class _TrumpeterFrame extends StatelessWidget {
  const _TrumpeterFrame({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('notification-trumpeter-frame'),
    width: size,
    height: size,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: _HeraldPalette.parchment,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: _HeraldPalette.brass, width: 2),
      boxShadow: [
        BoxShadow(
          color: _HeraldPalette.walnut.withValues(alpha: 0.25),
          offset: const Offset(0, 6),
          blurRadius: 0,
        ),
      ],
    ),
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: _HeraldPalette.parchmentSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg - 6),
        border: Border.all(color: _HeraldPalette.outline),
      ),
      clipBehavior: Clip.hardEdge,
      child: Semantics(
        image: true,
        label: '전령 도담이',
        child: ExcludeSemantics(
          child: Image.asset(
            'assets/characters/dodami_trumpeter_profile.png',
            key: const ValueKey('notification-trumpeter-character'),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    ),
  );
}

class _HeraldDecoration extends StatelessWidget {
  const _HeraldDecoration();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Stack(
        children: [
          for (final alignment in const [
            Alignment(-0.96, -0.9),
            Alignment(0.96, -0.9),
            Alignment(-0.96, 0.9),
            Alignment(0.96, 0.9),
          ])
            Align(
              alignment: alignment,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _HeraldPalette.brass.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          Positioned(
            right: 24,
            bottom: 18,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final width in const [28.0, 42.0, 58.0]) ...[
                  Container(
                    width: width,
                    height: 2,
                    color: _HeraldPalette.brass.withValues(alpha: 0.14),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _NotificationTimelineEntry extends StatelessWidget {
  const _NotificationTimelineEntry({
    required this.item,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final NotificationItemDto item;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: SizedBox(
          width: 30,
          child: Column(
            children: [
              Container(
                width: 2,
                height: 20,
                color: isFirst
                    ? Colors.transparent
                    : AppColors.leaf.withValues(alpha: 0.28),
              ),
              Container(
                width: item.isRead ? 10 : 12,
                height: item.isRead ? 10 : 12,
                decoration: BoxDecoration(
                  color: item.isRead ? _HeraldPalette.brass : AppColors.leaf,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _HeraldPalette.parchmentSoft,
                    width: 2,
                  ),
                ),
              ),
              Container(
                width: 2,
                height: 56,
                color: isLast
                    ? Colors.transparent
                    : AppColors.leaf.withValues(alpha: 0.28),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: NotificationItemCard(item: item, onTap: onTap),
        ),
      ),
    ],
  );
}
