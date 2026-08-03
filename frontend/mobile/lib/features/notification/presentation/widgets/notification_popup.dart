import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/router/notification_route_resolver.dart';
import '../../../../design_system/design_system.dart';
import '../../application/notification_badge_controller.dart';
import '../../application/notification_read_marker.dart';
import '../../data/dto/notification_inbox_dtos.dart';
import '../../domain/failures/push_token_registration_failure.dart';
import '../../domain/repositories/notification_inbox_repository.dart';
import 'notification_item_card.dart';
import 'push_registration_notice.dart';

/// 알림 버튼 자리에서 최근 알림을 보여주는 팝업을 띄운다.
///
/// 열린 자리를 벗어나지 않게 [anchorRect]는 **전역 좌표**로 준다(버튼의
/// `RenderBox.localToGlobal`). 팝업은 안전 영역 안으로 눌러 담기므로 태블릿
/// 가로 화면에서도 잘리지 않는다.
///
/// 돌려주는 값은 사용자가 고른 이동 대상 라우트다. `null`이면 이동 없이 닫혔다.
/// 이동은 호출부가 [AppNavigation.pushNamed]로 수행한다 — 팝업이 닫히기 전에
/// 이동하면 팝업 라우트 위에 화면이 쌓이고, 중복 이동 판정도 팝업을 "지금
/// 화면"으로 본다(S15P11B209-501의 판정기를 그대로 쓰기 위한 조건).
Future<String?> showNotificationPopup(
  BuildContext context, {
  required Rect anchorRect,
  required NotificationInboxRepository repository,
  NotificationBadgeController? badgeController,
  ValueListenable<PushTokenRegistrationFailure?>? pushRegistrationStatus,
  VoidCallback? onDismissPushNotice,
  int recentCount = 5,
}) => showDialog<String>(
  context: context,
  barrierColor: Colors.black12,
  // 앵커는 전역 좌표라 좌표계를 옮기지 않는다. 안전 영역은 배치가 직접 뺀다.
  useSafeArea: false,
  builder: (_) => NotificationPopup(
    anchorRect: anchorRect,
    repository: repository,
    badgeController: badgeController,
    pushRegistrationStatus: pushRegistrationStatus,
    onDismissPushNotice: onDismissPushNotice,
    recentCount: recentCount,
  ),
);

/// [showNotificationPopup]이 띄우는 팝업 본체. 위젯 테스트에서 직접 세울 수 있게
/// 공개한다.
class NotificationPopup extends StatelessWidget {
  const NotificationPopup({
    required this.anchorRect,
    required this.repository,
    this.badgeController,
    this.pushRegistrationStatus,
    this.onDismissPushNotice,
    this.recentCount = 5,
    super.key,
  });

  static const panel = ValueKey('notification-popup');
  static const retryAction = ValueKey('notification-popup-retry');
  static const seeAllAction = ValueKey('notification-popup-see-all');

  final Rect anchorRect;
  final NotificationInboxRepository repository;
  final NotificationBadgeController? badgeController;
  final ValueListenable<PushTokenRegistrationFailure?>? pushRegistrationStatus;
  final VoidCallback? onDismissPushNotice;

  /// 팝업에 실을 최근 알림 건수. 나머지는 "전체 보기"가 담당한다.
  final int recentCount;

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.paddingOf(context);
    return CustomSingleChildLayout(
      delegate: NotificationPopupLayout(
        anchorRect: anchorRect,
        margin: EdgeInsets.fromLTRB(
          safeArea.left + AppSpacing.md,
          safeArea.top + AppSpacing.xs,
          safeArea.right + AppSpacing.md,
          safeArea.bottom + AppSpacing.md,
        ),
      ),
      child: _NotificationPopupPanel(
        repository: repository,
        badgeController: badgeController,
        pushRegistrationStatus: pushRegistrationStatus,
        onDismissPushNotice: onDismissPushNotice,
        recentCount: recentCount,
      ),
    );
  }
}

/// 앵커 아래(공간이 없으면 위)에 팝업을 붙이고 화면 안으로 눌러 담는다.
@visibleForTesting
final class NotificationPopupLayout extends SingleChildLayoutDelegate {
  const NotificationPopupLayout({
    required this.anchorRect,
    required this.margin,
    this.gap = AppSpacing.xs,
    this.maxPanelWidth = 380,
    this.minPanelHeight = 220,
  });

  /// 알림 버튼의 전역 좌표 사각형.
  final Rect anchorRect;

  /// 화면 가장자리에서 남겨 둘 여백(안전 영역 포함).
  final EdgeInsets margin;
  final double gap;
  final double maxPanelWidth;

  /// 아래·위 어느 쪽에도 이만큼이 없으면 화면 안으로 눌러 담아 겹치게 둔다.
  /// 완전히 사라지는 것보다 앵커를 조금 덮는 편이 낫다.
  final double minPanelHeight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.max(
      0.0,
      math.min(maxPanelWidth, constraints.maxWidth - margin.horizontal),
    );
    final below =
        constraints.maxHeight - margin.bottom - anchorRect.bottom - gap;
    final above = anchorRect.top - gap - margin.top;
    final roomiest = math.max(below, above);
    final height = math.max(
      0.0,
      math.min(
        constraints.maxHeight - margin.vertical,
        math.max(roomiest, minPanelHeight),
      ),
    );
    // 너비는 고정, 높이는 내용에 맞춘다 — 알림 한 건만 있어도 화면을 가리지 않는다.
    return BoxConstraints(minWidth: width, maxWidth: width, maxHeight: height);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // 버튼 오른쪽 끝에 맞춰 열고, 왼쪽으로 넘치면 여백까지만 밀어 넣는다.
    final maxLeft = math.max(
      margin.left,
      size.width - margin.right - childSize.width,
    );
    final left = math.min(
      math.max(anchorRect.right - childSize.width, margin.left),
      maxLeft,
    );

    final below = anchorRect.bottom + gap;
    if (below + childSize.height <= size.height - margin.bottom) {
      return Offset(left, below);
    }
    final above = anchorRect.top - gap - childSize.height;
    if (above >= margin.top) return Offset(left, above);
    return Offset(
      left,
      math.max(margin.top, size.height - margin.bottom - childSize.height),
    );
  }

  @override
  bool shouldRelayout(NotificationPopupLayout oldDelegate) =>
      oldDelegate.anchorRect != anchorRect ||
      oldDelegate.margin != margin ||
      oldDelegate.gap != gap ||
      oldDelegate.maxPanelWidth != maxPanelWidth ||
      oldDelegate.minPanelHeight != minPanelHeight;
}

class _NotificationPopupPanel extends StatefulWidget {
  const _NotificationPopupPanel({
    required this.repository,
    required this.recentCount,
    this.badgeController,
    this.pushRegistrationStatus,
    this.onDismissPushNotice,
  });

  final NotificationInboxRepository repository;
  final int recentCount;
  final NotificationBadgeController? badgeController;
  final ValueListenable<PushTokenRegistrationFailure?>? pushRegistrationStatus;
  final VoidCallback? onDismissPushNotice;

  @override
  State<_NotificationPopupPanel> createState() =>
      _NotificationPopupPanelState();
}

class _NotificationPopupPanelState extends State<_NotificationPopupPanel> {
  late final NotificationReadMarker _readMarker = NotificationReadMarker(
    widget.repository,
    badgeController: widget.badgeController,
  );

  final List<NotificationItemDto> _items = [];
  bool _isLoading = true;
  bool _hasReadError = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final page = await widget.repository.getNotifications(
        filter: NotificationFilterDto(size: widget.recentCount),
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.content);
      });
      // 팝업을 여는 것도 보호자가 알림을 확인하는 지점이다. 목록 왕복에 곁들여
      // 미열람 수를 다시 세어, 배지가 푸시 수신에만 의존하지 않게 한다. 왕복을
      // 기다리지 않아 팝업 표시가 늦어지지 않는다.
      unawaited(widget.badgeController?.refresh());
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 알림함 목록 화면과 같은 규칙으로 읽음 처리하고 이동 대상을 고른다.
  ///
  /// 이동 대상은 푸시와 같은 매핑 함수가 정한다(S15P11B209-501, 푸시 계약 §4.3).
  /// 연결 자원이 없으면 갈 곳이 없으니 팝업에 머문다 — 목록 화면도 같다.
  void _handleCardTap(NotificationItemDto item) {
    unawaited(_markRead(item));

    final route = resolveNotificationItemRoute(
      relatedResourceType: item.relatedResourceType,
      relatedResourceId: item.relatedResourceId,
    );
    if (route == null) return;

    Navigator.of(context).pop(route);
  }

  Future<void> _markRead(NotificationItemDto item) async {
    final result = await _readMarker.markRead(item);
    if (!mounted) return;
    if (result.outcome == NotificationReadOutcome.failure) {
      setState(() => _hasReadError = true);
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

  @override
  Widget build(BuildContext context) => Material(
    key: NotificationPopup.panel,
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(AppRadius.lg),
    clipBehavior: Clip.antiAlias,
    elevation: 8,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        if (widget.pushRegistrationStatus case final status?)
          ValueListenableBuilder<PushTokenRegistrationFailure?>(
            valueListenable: status,
            builder: (context, failure, _) => failure == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      0,
                      AppSpacing.sm,
                      AppSpacing.sm,
                    ),
                    child: PushRegistrationNotice(
                      failure: failure,
                      onDismiss: widget.onDismissPushNotice,
                      dense: true,
                    ),
                  ),
          ),
        if (_hasReadError)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Text(
              '알림을 읽음 처리하지 못했어요.',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Flexible(child: _buildBody()),
        const Divider(height: 1, color: AppColors.outline),
        _buildFooter(),
      ],
    ),
  );

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.sm,
      AppSpacing.xs,
    ),
    child: Row(
      children: [
        const Expanded(child: Text('알림', style: AppTypography.titleMd)),
        if (widget.badgeController case final badge?)
          ValueListenableBuilder<int>(
            valueListenable: badge,
            builder: (context, value, _) => Text(
              value > 0 ? '읽지 않음 $value건' : '모두 확인했어요',
              style: AppTypography.caption,
            ),
          ),
        const SizedBox(width: AppSpacing.xs),
      ],
    ),
  );

  Widget _buildBody() {
    if (_isLoading) {
      return const SizedBox(
        height: 132,
        child: Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return _PopupMessage(
        message: '알림을 불러오지 못했어요.',
        action: TextButton(
          key: NotificationPopup.retryAction,
          onPressed: _load,
          child: const Text('다시 시도'),
        ),
      );
    }
    if (_items.isEmpty) {
      return const _PopupMessage(message: '아직 알림이 없어요.');
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final item = _items[index];
        return NotificationItemCard(
          key: ValueKey('notification-popup-item-${item.notificationId}'),
          item: item,
          dense: true,
          onTap: () => _handleCardTap(item),
        );
      },
    );
  }

  Widget _buildFooter() => InkWell(
    key: NotificationPopup.seeAllAction,
    onTap: () => Navigator.of(context).pop(AppRoutes.notifications),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('전체 보기', style: AppTypography.button),
          Icon(
            Icons.chevron_right_rounded,
            size: AppIconSize.md,
            color: AppColors.inkMuted,
          ),
        ],
      ),
    ),
  );
}

class _PopupMessage extends StatelessWidget {
  const _PopupMessage({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.lg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center, style: AppTypography.bodySm),
        if (action case final resolved?) ...[
          const SizedBox(height: AppSpacing.xxs),
          resolved,
        ],
      ],
    ),
  );
}
