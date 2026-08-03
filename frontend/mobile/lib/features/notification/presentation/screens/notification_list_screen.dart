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
          return NotificationItemCard(
            item: item,
            onTap: () => _handleCardTap(item),
          );
        },
      ),
    );
  }
}
