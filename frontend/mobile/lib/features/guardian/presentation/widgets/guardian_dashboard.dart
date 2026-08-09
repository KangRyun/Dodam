import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/app_router.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/state/guardian_child_controller.dart';
import '../../../activity/data/dto/activity_dtos.dart';
import '../../../activity/domain/repositories/activity_repository.dart';
import '../../../child/data/dto/child_dtos.dart';
import '../../../drawing/presentation/widgets/htp_intro_dialog.dart';
import '../../../notification/application/notification_badge_controller.dart';
import '../../../notification/application/push_registration_status_controller.dart';
import '../../../notification/domain/failures/push_token_registration_failure.dart';
import '../../../notification/domain/repositories/notification_inbox_repository.dart';
import '../../../notification/presentation/widgets/notification_popup.dart';
import '../../../notification/presentation/widgets/push_registration_notice.dart';
import 'guardian_home_theme.dart';
import 'mind_calendar_card.dart';
import 'mind_emotion.dart';

/// 보호자 홈 대시보드 본문(시안 1:1). 헤더 + 2단 그리드(왼쪽 마음카드+최근활동 /
/// 오른쪽 마음 달력). 아이가 바뀌면 상위에서 ValueKey로 다시 만들어 재로딩한다.
class GuardianDashboard extends StatefulWidget {
  const GuardianDashboard({
    required this.controller,
    this.activityRepository,
    this.notificationInboxRepository,
    this.notificationBadgeController,
    this.pushRegistrationStatus,
    super.key,
  });

  final GuardianChildController controller;
  final ActivityRepository? activityRepository;

  /// 헤더 알림 버튼이 여는 팝업이 읽을 알림함. 주지 않으면 팝업 대신 사이드바
  /// 알림함으로 안내한다(로그인 전·목 구성).
  final NotificationInboxRepository? notificationInboxRepository;

  /// 미열람 수. 헤더 알림 버튼의 점 표시와 팝업 요약이 같은 값을 본다.
  final NotificationBadgeController? notificationBadgeController;

  /// 이 기기가 푸시를 받지 못하는 상태인지. 값이 있으면 안내 띠를 띄운다.
  final PushRegistrationStatusController? pushRegistrationStatus;

  @override
  State<GuardianDashboard> createState() => _GuardianDashboardState();
}

class _GuardianDashboardState extends State<GuardianDashboard> {
  Future<List<ActivitySummaryDto>>? _recentFuture;

  @override
  void initState() {
    super.initState();
    _recentFuture = _loadRecent();
  }

  Future<List<ActivitySummaryDto>> _loadRecent() async {
    final child = widget.controller.selectedChild;
    final repository = widget.activityRepository;
    if (child == null || repository == null) return const [];
    final page = await repository.getActivities(
      child.childId,
      filter: const ActivityFilterDto(size: 8),
    );
    return page.content;
  }

  /// 2단 그리드와 마음 달력이 더는 줄어들 수 없는 최소 세로 높이.
  ///
  /// 왼쪽 마음카드가 아이 chip 개수만큼 커질 때는 이 값에 억지로 맞추지 않고
  /// [_buildTwoColumnBody]가 자연 높이로 더 커진다. 부모 CustomScrollView가 그
  /// 증가분을 스크롤하므로 최근 활동 카드가 남은 높이를 떠안지 않는다.
  static const double _bodyMinHeight = 600;

  /// 글자 배율이 커질 때 카드 안 텍스트·버튼이 함께 커지는 만큼의 추가 여유.
  ///
  /// 마음 달력의 날짜 셀은 `날짜 글자 + 3 + 원(최소 지름 12)`이 하한이라 글자
  /// 배율에 따라 6줄 전체가 함께 커진다. 배율 2.0까지 그 증가분을 덮는다.
  static const double _bodyTextScaleAllowance = 380;

  /// 2단 그리드를 유지할 수 있는 최소 본문 폭.
  ///
  /// 이보다 좁으면 마음카드·최근 활동·마음 달력이 각각 절반도 못 받아 카드 내부
  /// Row와 달력 셀이 가로로 넘친다. 좁은 화면은 한 열로 쌓아 폭을 온전히 준다.
  static const double _twoColumnMinWidth = 720;

  /// 한 열로 쌓을 때 마음 달력에 주는 높이(글자 배율 1.0 기준).
  ///
  /// 달력은 머리말·요약·요일·범례가 고정이고 날짜 격자만 늘어난다. 6줄 × 날짜 셀
  /// 하한(약 29)을 격자에 남겨야 셀이 잘리지 않는다.
  static const double _stackedCalendarHeight = 440;

  /// 보호자 홈 전체 글자 확대 배수. 화면 전반(헤더·프로필·카드·달력)을 균일하게
  /// 키우기 위해 서브트리의 텍스트 스케일러에 곱한다.
  static const double _uiTextScale = 1.4;

  @override
  Widget build(BuildContext context) {
    final baseFactor = MediaQuery.textScalerOf(context).scale(1);
    final scaledFactor = baseFactor * _uiTextScale;
    // 글자 배율이 커지면 카드 안 텍스트·버튼이 함께 커져 최소 높이도 늘어난다.
    // 기본 1.4배 위에 OS 접근성 배율까지 얹힐 수 있어 상한을 넉넉히 잡는다.
    final scaleAllowance = (scaledFactor - 1).clamp(0.0, 1.8);
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scaledFactor)),
      child: Container(
        key: const ValueKey('child-list-success'),
        padding: const EdgeInsets.fromLTRB(30, 24, 30, 22),
        // 넓은 태블릿에서 헤더·2열 그리드가 화면 끝까지 늘어나지 않도록 본문을
        // 최대 폭으로 가두고 가운데 정렬한다(S15P11B209-787). 다만 2열 배치는
        // 폭을 넉넉히 써야 좌우 여백이 어색하지 않으므로, 이 화면만 상한을 넓게
        // 잡는다(갤럭시 탭 S10 Ultra 등 초광폭 태블릿 대응).
        child: ResponsiveContent(
          maxWidth: 1440,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bodySliver = _buildBodySliver(
                maxWidth: constraints.maxWidth,
                scaleAllowance: scaleAllowance,
              );
              // 헤더 블록만으로도 화면을 넘기는 극단 조합(아주 낮은 높이 + 큰 글자 배율
              // + 푸시 안내 띠)에서는 헤더를 스크롤 밖에 두면 헤더가 넘치고 본문 몫이
              // 0이 된다. 그때만 헤더까지 같은 스크롤에 넣는다.
              if (constraints.maxHeight <
                  _headerOutsideMinHeight(scaleAllowance)) {
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    bodySliver,
                  ],
                );
              }
              // 평소에는 헤더와 푸시 안내를 스크롤 밖에 두어 항상 보이고 본문만
              // 스크롤한다. 본문에 남은 높이가 최소 높이보다 작을 때만 스크롤이
              // 생긴다 — 여유가 있는 화면에서는 스크롤 범위가 0이라 기존 배치와 같다.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  Expanded(child: CustomScrollView(slivers: [bodySliver])),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 헤더를 스크롤 밖에 둘 수 있는 최소 화면 높이.
  ///
  /// 실측 헤더 높이는 배율 1.0에서 72, 2.0에서 125이고 푸시 안내 띠가 그만큼 더
  /// 붙는다. 여기에 본문이 최소한 보일 몫을 더해 판단한다.
  double _headerOutsideMinHeight(double scaleAllowance) {
    final header = 72 + 60 * scaleAllowance;
    final banner = widget.pushRegistrationStatus == null
        ? 0
        : 72 + 60 * scaleAllowance;
    return header + banner + _bodyVisibleMinHeight;
  }

  /// 헤더를 고정으로 둘 때 본문에 최소한 남겨야 하는 높이.
  static const double _bodyVisibleMinHeight = 120;

  Widget _buildBodySliver({
    required double maxWidth,
    required double scaleAllowance,
  }) {
    if (maxWidth < _twoColumnMinWidth) {
      return SliverToBoxAdapter(
        child: _buildStackedBody(scaleAllowance: scaleAllowance),
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final viewportRemainder =
            constraints.viewportMainAxisExtent -
            constraints.precedingScrollExtent;
        final baseHeight =
            _bodyMinHeight + _bodyTextScaleAllowance * scaleAllowance;
        final minHeight = viewportRemainder > baseHeight
            ? viewportRemainder
            : baseHeight;
        return SliverToBoxAdapter(
          child: _buildTwoColumnBody(minHeight: minHeight),
        );
      },
    );
  }

  Widget _buildHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Header(
        child: widget.controller.selectedChild,
        notificationInboxRepository: widget.notificationInboxRepository,
        notificationBadgeController: widget.notificationBadgeController,
        pushRegistrationStatus: widget.pushRegistrationStatus,
      ),
      if (widget.pushRegistrationStatus case final status?)
        _PushRegistrationBanner(status: status),
      const SizedBox(height: 16),
    ],
  );

  Widget _buildTwoColumnBody({required double minHeight}) {
    final selected = widget.controller.selectedChild;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 92,
          child: SizedBox(
            // 오른쪽 마음 달력과 같은 높이로 맞추고, 남는 높이는 활동 카드가 채운다.
            height: minHeight,
            child: _HeroCard(
              controller: widget.controller,
              selected: selected,
              recentFuture: _recentFuture,
              fillHeight: true,
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 108,
          child: SizedBox(
            height: minHeight,
            child: _CalendarSection(
              childId: selected?.childId,
              childName: selected?.nickname,
              repository: widget.activityRepository,
            ),
          ),
        ),
      ],
    );
  }

  /// 좁은 화면 배치. 카드마다 폭을 온전히 주고 세로로 쌓아 스크롤한다.
  ///
  /// 최근 활동 카드와 마음 달력은 내부에 [Expanded]가 있어 유한한 높이가 필요하다.
  /// 여기서는 채울 남은 높이가 없으므로 각자 명시 높이를 준다.
  Widget _buildStackedBody({required double scaleAllowance}) {
    final selected = widget.controller.selectedChild;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(
          controller: widget.controller,
          selected: selected,
          recentFuture: _recentFuture,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height:
              _stackedCalendarHeight + _bodyTextScaleAllowance * scaleAllowance,
          child: _CalendarSection(
            childId: selected?.childId,
            childName: selected?.nickname,
            repository: widget.activityRepository,
          ),
        ),
      ],
    );
  }
}

// ── 헤더 ─────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({
    required this.child,
    required this.notificationInboxRepository,
    required this.notificationBadgeController,
    required this.pushRegistrationStatus,
  });
  final ChildSummaryDto? child;
  final NotificationInboxRepository? notificationInboxRepository;
  final NotificationBadgeController? notificationBadgeController;
  final PushRegistrationStatusController? pushRegistrationStatus;

  static String _relLabel(String? rel) => switch (rel) {
    'MOTHER' => '엄마',
    'FATHER' => '아빠',
    'GRANDPARENT' => '조부모',
    _ => '보호자',
  };

  @override
  Widget build(BuildContext context) {
    final greeting = child == null
        ? '안녕하세요, 보호자님 🌱'
        : '안녕하세요, ${child!.nickname} ${_relLabel(child!.relationshipType)}님 🌱';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '보호자 홈',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: DodamHome.pointDeep,
                  letterSpacing: 0.72,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                greeting,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  color: DodamHome.ink,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        _IconBtn(
          icon: Icons.help_outline_rounded,
          tooltip: '도움말',
          onTap: () => _snack(context, '도움말은 준비 중이에요.'),
        ),
        const SizedBox(width: 10),
        _NotificationButton(
          repository: notificationInboxRepository,
          badgeController: notificationBadgeController,
          pushRegistrationStatus: pushRegistrationStatus,
        ),
      ],
    );
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 헤더 알림 버튼. 누르면 그 자리에 최근 알림 팝업을 띄운다.
///
/// 팝업이 고른 이동 대상은 팝업이 닫힌 뒤 여기서 연다. 이동은 사이드바 알림함이
/// 쓰는 진입점([AppNavigation.pushNamed])과 같아, 중복 이동 판정도 같이 걸린다
/// (S15P11B209-501).
class _NotificationButton extends StatefulWidget {
  const _NotificationButton({
    required this.repository,
    required this.badgeController,
    required this.pushRegistrationStatus,
  });

  final NotificationInboxRepository? repository;
  final NotificationBadgeController? badgeController;
  final PushRegistrationStatusController? pushRegistrationStatus;

  @override
  State<_NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<_NotificationButton> {
  /// 팝업을 붙일 기준. 버튼의 전역 좌표를 팝업 배치에 넘긴다.
  final _anchorKey = GlobalKey();
  bool _isOpen = false;

  Future<void> _openPopup() async {
    final repository = widget.repository;
    if (repository == null) {
      _Header._snack(context, '로그인 후 알림을 확인할 수 있어요.');
      return;
    }
    // 연타로 팝업이 겹쳐 열리면 뒤에 남은 것이 화면을 덮는다.
    if (_isOpen) return;
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    setState(() => _isOpen = true);
    final route = await showNotificationPopup(
      context,
      anchorRect: box.localToGlobal(Offset.zero) & box.size,
      repository: repository,
      badgeController: widget.badgeController,
      pushRegistrationStatus: widget.pushRegistrationStatus,
      onDismissPushNotice: widget.pushRegistrationStatus?.dismiss,
    );
    if (!mounted) return;
    setState(() => _isOpen = false);
    if (route == null) return;

    AppNavigation.pushNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final badge = widget.badgeController;
    final button = _IconBtn(
      key: _anchorKey,
      icon: Icons.notifications_none_rounded,
      tooltip: '알림',
      onTap: _openPopup,
    );
    if (badge == null) return button;

    return ValueListenableBuilder<int>(
      valueListenable: badge,
      builder: (context, value, _) => _IconBtn(
        key: _anchorKey,
        icon: Icons.notifications_none_rounded,
        tooltip: '알림',
        // 미열람이 있을 때만 점을 켠다. 예전에는 항상 켜져 있어 읽을 알림이
        // 없어도 새 소식이 있는 것처럼 보였다.
        showDot: value > 0,
        onTap: _openPopup,
      ),
    );
  }
}

/// 푸시를 받지 못하는 상태를 보호자 홈 상단에 알린다.
///
/// 아동 화면에는 올리지 않는다 — 이 위젯은 보호자 대시보드에만 있다.
class _PushRegistrationBanner extends StatelessWidget {
  const _PushRegistrationBanner({required this.status});

  final PushRegistrationStatusController status;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<PushTokenRegistrationFailure?>(
        valueListenable: status,
        builder: (context, failure, _) => failure == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 12),
                child: PushRegistrationNotice(
                  failure: failure,
                  onDismiss: status.dismiss,
                ),
              ),
      );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.showDot = false,
    super.key,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: DodamHome.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DodamHome.line),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 22, color: DodamHome.ink),
              if (showDot)
                Positioned(
                  top: 11,
                  right: 12,
                  child: Container(
                    key: const ValueKey('guardian-header-dot'),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: DodamHome.coral,
                      shape: BoxShape.circle,
                      border: Border.all(color: DodamHome.surface, width: 2),
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

// ── 카드 공통 ────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: DodamHome.surface,
      border: Border.all(color: DodamHome.line),
      borderRadius: BorderRadius.circular(22),
      boxShadow: DodamHome.cardShadow,
    ),
    child: child,
  );
}

// ── 히어로(마음 카드) ────────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.controller,
    required this.selected,
    required this.recentFuture,
    this.fillHeight = false,
  });
  final GuardianChildController controller;
  final ChildSummaryDto? selected;
  final Future<List<ActivitySummaryDto>>? recentFuture;

  /// 2열 배치에서 카드가 마음 달력 높이만큼 늘어날 때 true.
  /// 남는 세로 공간을 CTA가 흡수해 크게 보이도록 한다.
  final bool fillHeight;

  static const _heroAsset = 'assets/characters/dodami_yellow.png';

  @override
  Widget build(BuildContext context) {
    final child = selected;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [DodamHome.heroTop, DodamHome.heroBottom],
        ),
        border: Border.all(color: DodamHome.heroBorder),
        borderRadius: BorderRadius.circular(22),
        boxShadow: DodamHome.cardShadow,
      ),
      child: Column(
        children: [
          _MiniSwitch(controller: controller),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Image.asset(
              _heroAsset,
              width: 108,
              fit: BoxFit.contain,
              semanticLabel: '도담이',
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox(height: 108),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            child == null ? '아이를 선택해 주세요' : '${child.nickname} · ${child.age}세',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: DodamHome.ink,
            ),
          ),
          if (child != null) ...[
            const SizedBox(height: 2),
            Text(
              '활동 ${child.recentActivity.totalActivityCount}회',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DodamHome.inkSoft,
              ),
            ),
          ],
          const SizedBox(height: 6),
          _MoodPill(child: child, recentFuture: recentFuture),
          const SizedBox(height: 16),
          // 활동 카드가 남는 세로 공간을 채워 왼쪽 블록을 달력 높이에 맞춘다.
          if (fillHeight)
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: _buildCta(context, child, tall: true),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: _buildCta(context, child, tall: false),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _ReportButton(recentFuture: recentFuture),
          ),
        ],
      ),
    );
  }

  Widget _buildCta(
    BuildContext context,
    ChildSummaryDto? child, {
    required bool tall,
  }) => _ActivityCard(
    enabled: child != null,
    tall: tall,
    onTap: child == null
        ? null
        : () async {
            // 활동을 시작하기 전에 HTP 소개 팝업을 먼저 띄우고,
            // "시작하기"를 눌렀을 때만 기존 활동 흐름으로 넘어간다
            // (S15P11B209-462).
            final start = await showHtpIntroDialog(context);
            if (start != true || !context.mounted) return;
            AppNavigation.pushNamed(
              context,
              AppRoutes.drawingActivitySelection(child.childId.toString()),
              arguments: const DrawingActivitySelectionRouteArguments(
                initialActivityCode: 'HTP',
              ),
              rootNavigator: true,
            );
          },
  );
}

class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({required this.controller});
  final GuardianChildController controller;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 7,
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final child in controller.children)
        _MiniKid(
          key: ValueKey('child-${child.childId}'),
          child: child,
          selected: controller.selectedChildId == child.childId,
          onTap: () => controller.selectChild(child),
        ),
      _MiniAdd(
        onTap: () => AppNavigation.pushNamed(context, AppRoutes.childRegister),
      ),
    ],
  );
}

class _MiniKid extends StatelessWidget {
  const _MiniKid({
    required this.child,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final ChildSummaryDto child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: DodamHome.surface,
    shape: StadiumBorder(
      side: BorderSide(
        color: selected ? DodamHome.pointDeep : DodamHome.chipBorder,
        width: 1.5,
      ),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3, 3, 12, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: DodamHome.pointSoft,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Image.asset(
                  'assets/characters/emotions/dodam_emotion_calm.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(width: 7),
            // 이름이 길면 칩이 Wrap 폭을 넘어 가로로 넘친다. 칩을 남은 폭 안에
            // 두기 위해 라벨만 줄인다(S15P11B209-848).
            Flexible(
              child: Text(
                child.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: DodamHome.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MiniAdd extends StatelessWidget {
  const _MiniAdd({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: const StadiumBorder(
      side: BorderSide(
        color: DodamHome.chipBorder,
        width: 1.5,
        style: BorderStyle.solid,
      ),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: const SizedBox(
        width: 32,
        height: 32,
        child: Icon(Icons.add_rounded, size: 16, color: DodamHome.inkSoft),
      ),
    ),
  );
}

class _MoodPill extends StatelessWidget {
  const _MoodPill({required this.child, required this.recentFuture});
  final ChildSummaryDto? child;
  final Future<List<ActivitySummaryDto>>? recentFuture;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ActivitySummaryDto>>(
    future: recentFuture,
    builder: (context, snapshot) {
      final activities = snapshot.data ?? const <ActivitySummaryDto>[];
      final latest = activities.isEmpty ? null : activities.first;
      final emotion = latest == null
          ? null
          : MindEmotion.fromApi(
              latest.selectedEmotions.isEmpty
                  ? null
                  : latest.selectedEmotions.first,
            );
      final label = emotion?.label ?? '기록 없음';
      final ago = _agoText(child?.recentActivity.lastActivityAt);
      final text = ago == null ? '마지막 마음 · $label' : '마지막 마음 · $label · $ago';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        decoration: BoxDecoration(
          color: DodamHome.surface,
          border: Border.all(color: DodamHome.heroBorder),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: emotion?.background ?? DodamHome.moodDot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: DodamHome.navOn,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  static String? _agoText(String? iso) {
    if (iso == null) return null;
    final at = DateTime.tryParse(iso)?.toLocal();
    if (at == null) return null;
    final days = DateTime.now().difference(at).inDays;
    if (days <= 0) return '오늘';
    return '$days일 전';
  }
}

/// 집·나무·사람 그림 활동 카드.
///
/// 세로 흐름: 제목 → 안내 문구 → 집·나무·사람 일러스트 → 하단 full-width 초록
/// CTA. 카드 배경은 알림 톤의 세이지, CTA만 선명한 초록을 쓴다. 카드가 마음 달력
/// 높이만큼 늘어나면([tall]) 일러스트를 크게 키우고 버튼을 아래로 고정한다.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.enabled,
    required this.onTap,
    this.tall = false,
  });
  final bool enabled;
  final VoidCallback? onTap;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('htp-activity-card'),
      decoration: BoxDecoration(
        color: DodamHome.htpCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DodamHome.forest.withValues(alpha: 0.14)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 카드는 콘텐츠에 맞는 자연 높이(min)로 두어 블록을 짧게 유지한다.
          // 일러스트는 폭에만 맞춰 크기를 정하고, 이미지 자체의 위·아래 여백은
          // Transform으로 살짝 겹쳐 문구·버튼과의 간격을 좁힌다.
          // 일러스트는 3칸이라 폭 상한(카드폭/3)을 넘으면 겹치므로 그 안에서
          // 최대한 키운다. 스트레치(2열)에서는 남는 높이만큼도 키운다.
          final capByWidth = (constraints.maxWidth - 28) / 3;
          final capByKind = tall ? 200.0 : 92.0;
          final capW = capByWidth < capByKind ? capByWidth : capByKind;
          const reservedFixed = 180.0; // 제목·안내·버튼·간격 실측 여유
          final byHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight - reservedFixed
              : capW;
          final illo = (byHeight < capW ? byHeight : capW).clamp(0.0, 200.0);
          return Column(
            mainAxisSize: tall ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '집·나무·사람 그림 활동',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: DodamHome.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '그림을 그리고, 아이의 이야기를 들어봐요.',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: DodamHome.inkSoft,
                ),
              ),
              if (tall)
                Expanded(
                  child: Center(child: _HtpIllustrations(size: illo)),
                )
              else ...[
                const SizedBox(height: 6),
                _HtpIllustrations(size: illo),
              ],
              Transform.translate(
                offset: Offset(0, tall ? -8 : -18),
                child: _StartActivityButton(
                  enabled: enabled,
                  onTap: onTap,
                  compact: !tall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 집·나무·사람(HTP) 손그림을 번호와 점선으로 연결한다.
///
/// 순서 정보는 하나의 Semantics 문구로 제공하고, 번호 마커·점선은
/// 중복 낭독되지 않도록 장식으로 처리한다.
class _HtpIllustrations extends StatelessWidget {
  const _HtpIllustrations({required this.size});
  final double size;

  static const _items = <(String, String)>[
    ('assets/characters/htp/htp_house.png', '집'),
    ('assets/characters/htp/htp_tree.png', '나무'),
    ('assets/characters/htp/htp_person.png', '사람'),
  ];

  @override
  Widget build(BuildContext context) {
    final gap = (size * 0.16).clamp(8.0, 14.0);
    return Semantics(
      container: true,
      label: '집, 나무, 사람 순서로 그리는 활동',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0)
                SizedBox(
                  width: gap,
                  height: size,
                  child: CustomPaint(
                    key: ValueKey('htp-sequence-connector-$i'),
                    painter: const _CrayonDashPainter(),
                  ),
                ),
              SizedBox(
                width: size,
                height: size,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned.fill(
                      top: (size * 0.10).clamp(4.0, 14.0),
                      child: Image.asset(
                        _items[i].$1,
                        key: ValueKey('htp-sequence-image-${i + 1}'),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    _HtpStepMarker(step: i + 1, size: size),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HtpStepMarker extends StatelessWidget {
  const _HtpStepMarker({required this.step, required this.size});

  final int step;
  final double size;

  @override
  Widget build(BuildContext context) {
    final markerSize = (size * 0.24).clamp(20.0, 28.0);
    return ExcludeSemantics(
      child: Container(
        key: ValueKey('htp-step-marker-$step'),
        width: markerSize,
        height: markerSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DodamHome.htpConnector,
          shape: BoxShape.circle,
          border: Border.all(color: DodamHome.warm, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: DodamHome.forest.withValues(alpha: 0.16),
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          '$step',
          style: TextStyle(
            color: Colors.white,
            fontSize: markerSize * 0.52,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _CrayonDashPainter extends CustomPainter {
  const _CrayonDashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = Path()
      ..moveTo(0, size.height * 0.56)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.68,
        size.width,
        size.height * 0.56,
      );
    final paint = Paint()
      ..color = DodamHome.htpConnector
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = (start + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CrayonDashPainter oldDelegate) => false;
}

/// 하단 메인 CTA 버튼. 선명한 초록 채움 + 흰 글자, hover 시 진해지고 화살표가
/// 살짝 이동하며, press·focus 상태를 함께 처리한다. 접근성을 위해 모션 축소를
/// 존중한다. 활동 진입 라우팅과 테스트 식별자(start-child-mode)를 유지한다.
class _StartActivityButton extends StatefulWidget {
  const _StartActivityButton({
    required this.enabled,
    required this.onTap,
    this.compact = false,
  });
  final bool enabled;
  final VoidCallback? onTap;
  final bool compact;

  @override
  State<_StartActivityButton> createState() => _StartActivityButtonState();
}

class _StartActivityButtonState extends State<_StartActivityButton> {
  bool _hovering = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motion = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final hovering = widget.enabled && _hovering;
    final pressed = widget.enabled && _pressed;
    final bg = pressed
        ? DodamHome.htpCtaPressed
        : hovering
        ? DodamHome.htpCtaHover
        : DodamHome.htpCta;
    final arrowGap = (hovering && !reduceMotion) ? 10.0 : 6.0;

    // 눌림 피드백은 InkWell 기본 하이라이트/스플래시로 처리한다(별도 Transform은
    // 좌표 기반 탭 테스트를 방해하므로 쓰지 않는다). hover 시 색을 진하게 하고
    // 화살표를 살짝 이동, focus 시 링을 그린다.
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '집 나무 사람 그림 활동 시작하기',
      onTap: widget.enabled ? widget.onTap : null,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // 단일 InkWell만 제스처를 잡아 탭 라우팅과 hover/focus를 모두 처리한다.
          key: const ValueKey('start-child-mode'),
          borderRadius: BorderRadius.circular(16),
          canRequestFocus: widget.enabled,
          mouseCursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          highlightColor: DodamHome.forest.withValues(alpha: 0.12),
          onTap: widget.enabled ? widget.onTap : null,
          onHover: (v) => setState(() => _hovering = v),
          onFocusChange: (v) => setState(() => _focused = v),
          onHighlightChanged: (v) => setState(() => _pressed = v),
          child: AnimatedContainer(
            key: const ValueKey('htp-start-button-surface'),
            duration: motion,
            curve: Curves.easeOut,
            // 세로 1.8배(52→94, 56→101)로 키워 클릭 영역을 크게 한다.
            constraints: BoxConstraints(minHeight: widget.compact ? 94 : 101),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: widget.enabled
                  ? bg
                  : DodamHome.htpCta.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.enabled
                    ? DodamHome.htpCtaBorder
                    : DodamHome.htpCtaBorder.withValues(alpha: 0.38),
                width: 1.75,
              ),
              boxShadow: [
                BoxShadow(
                  color: DodamHome.htpCtaBorder.withValues(alpha: 0.28),
                  blurRadius: pressed ? 2 : 4,
                  offset: Offset(0, pressed ? 1 : 3),
                ),
                if (_focused)
                  BoxShadow(
                    color: DodamHome.forest.withValues(alpha: 0.72),
                    spreadRadius: 2.5,
                  ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Flexible(
                  child: Text(
                    '집 나무 사람 그림 활동 시작하기',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: motion,
                  curve: Curves.easeOut,
                  width: arrowGap,
                ),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.recentFuture});
  final Future<List<ActivitySummaryDto>>? recentFuture;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ActivitySummaryDto>>(
    future: recentFuture,
    builder: (context, snapshot) {
      final activities = snapshot.data ?? const <ActivitySummaryDto>[];
      int? reportId;
      var hasNew = false;
      for (final activity in activities) {
        final report = activity.report;
        if (report != null && report.reportStatus == 'COMPLETED') {
          reportId = report.reportId;
          // "new!"는 새 리포트일 때만 — 최근 7일 내 완료된 활동의 리포트만
          // 표시한다(데이터에 열람 플래그가 없어 최신성으로 판단).
          final at = DateTime.tryParse(
            activity.completedAt ?? activity.startedAt,
          )?.toLocal();
          hasNew = at != null && DateTime.now().difference(at).inDays <= 7;
          break;
        }
      }
      // 버튼2 — 큰 CTA 아래 보조 버튼. 연한 초록 채움으로 CTA와 계열을 맞추되
      // 크기·채도를 낮춰 위계를 유지한다.
      final enabled = reportId != null;
      return Material(
        // 밝은 크림 배경 — 초록 CTA와 대비해 보조 동선임을 드러낸다.
        color: DodamHome.heroTop,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: DodamHome.line),
        ),
        child: InkWell(
          // 리포트가 있을 때만 키를 단다 — 키의 존재가 곧 "진입 가능"을 뜻하도록.
          key: enabled ? ValueKey('guardian-latest-report-$reportId') : null,
          borderRadius: BorderRadius.circular(14),
          onTap: enabled
              ? () => AppNavigation.pushNamed(
                  context,
                  AppRoutes.report(reportId!.toString()),
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: enabled ? DodamHome.forest : DodamHome.inkFaint,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '최신 리포트 보기',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: enabled ? DodamHome.forest : DodamHome.inkFaint,
                    ),
                  ),
                ),
                if (hasNew) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: DodamHome.coral,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'new!',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ── 우측 달력 ────────────────────────────────────────────────────────
class _CalendarSection extends StatelessWidget {
  const _CalendarSection({
    required this.childId,
    required this.childName,
    required this.repository,
  });
  final int? childId;
  final String? childName;
  final ActivityRepository? repository;

  @override
  Widget build(BuildContext context) {
    final id = childId;
    final repo = repository;
    // 달력도 왼쪽 블록과 같은 글자 배율(1.4배)을 그대로 받는다. 날짜 원 지름은
    // 글자 몫(줄 높이 -22)을 빼고 계산하므로 배율이 커져도 넘치지 않는다.
    if (id == null || repo == null) return const _Card(child: SizedBox());
    return MindCalendarCard(
      key: ValueKey('mind-calendar-$id'),
      childId: id,
      childName: childName,
      repository: repo,
    );
  }
}
