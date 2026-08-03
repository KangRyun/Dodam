import 'package:flutter/material.dart';

import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/app_router.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/state/guardian_child_controller.dart';
import '../../../activity/data/dto/activity_dtos.dart';
import '../../../activity/domain/repositories/activity_repository.dart';
import '../../../child/data/dto/child_dtos.dart';
import '../../../drawing/presentation/widgets/htp_intro_dialog.dart';
import 'guardian_home_theme.dart';
import 'mind_calendar_card.dart';
import 'mind_emotion.dart';

/// 보호자 홈 대시보드 본문(시안 1:1). 헤더 + 2단 그리드(왼쪽 마음카드+최근활동 /
/// 오른쪽 마음 달력). 아이가 바뀌면 상위에서 ValueKey로 다시 만들어 재로딩한다.
class GuardianDashboard extends StatefulWidget {
  const GuardianDashboard({
    required this.controller,
    this.activityRepository,
    super.key,
  });

  final GuardianChildController controller;
  final ActivityRepository? activityRepository;

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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final selected = controller.selectedChild;
    return Container(
      key: const ValueKey('child-list-success'),
      padding: const EdgeInsets.fromLTRB(30, 24, 30, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(child: selected),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 92,
                  child: Column(
                    children: [
                      _HeroCard(
                        controller: controller,
                        selected: selected,
                        recentFuture: _recentFuture,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _RecentActivityCard(recentFuture: _recentFuture),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  flex: 108,
                  child: _CalendarSection(
                    childId: selected?.childId,
                    childName: selected?.nickname,
                    repository: widget.activityRepository,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 헤더 ─────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.child});
  final ChildSummaryDto? child;

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
        _IconBtn(
          icon: Icons.notifications_none_rounded,
          tooltip: '알림',
          showDot: true,
          onTap: () => _snack(context, '알림은 왼쪽 사이드바 "알림"에서 확인할 수 있어요.'),
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

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.showDot = false,
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
  });
  final GuardianChildController controller;
  final ChildSummaryDto? selected;
  final Future<List<ActivitySummaryDto>>? recentFuture;

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
          const SizedBox(height: 12),
          _Cta(
            enabled: child != null,
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
                      AppRoutes.drawingActivitySelection(
                        child.childId.toString(),
                      ),
                      arguments: const DrawingActivitySelectionRouteArguments(
                        initialActivityCode: 'HTP',
                      ),
                      rootNavigator: true,
                    );
                  },
          ),
          const SizedBox(height: 8),
          _ReportButton(recentFuture: recentFuture),
        ],
      ),
    );
  }
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
            Text(
              child.nickname,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: DodamHome.ink,
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

class _Cta extends StatelessWidget {
  const _Cta({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.5,
    child: Material(
      key: const ValueKey('start-child-mode'),
      color: DodamHome.point,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: const SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_outlined, size: 20, color: DodamHome.onPoint),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  '집·나무·사람 그림 활동하기',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: DodamHome.onPoint,
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
      return Material(
        color: hasNew ? DodamHome.pointSoft : DodamHome.surface,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          // 리포트가 있을 때만 키를 단다 — 키의 존재가 곧 "진입 가능"을 뜻하도록.
          key: reportId == null
              ? null
              : ValueKey('guardian-latest-report-$reportId'),
          borderRadius: BorderRadius.circular(13),
          onTap: reportId == null
              ? null
              : () => AppNavigation.pushNamed(
                  context,
                  AppRoutes.report(reportId.toString()),
                ),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: hasNew ? DodamHome.pointDeep : DodamHome.line,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: DodamHome.ink,
                ),
                const SizedBox(width: 8),
                const Text(
                  '최신 리포트 보기',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: DodamHome.ink,
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

// ── 최근 활동 ────────────────────────────────────────────────────────
class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.recentFuture});
  final Future<List<ActivitySummaryDto>>? recentFuture;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '최근 활동',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: DodamHome.ink,
                ),
              ),
            ),
            InkWell(
              key: const ValueKey('activity-history-entry'),
              onTap: () =>
                  AppNavigation.pushNamed(context, AppRoutes.activityHistory),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '전체',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: DodamHome.inkSoft,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: DodamHome.inkSoft,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<ActivitySummaryDto>>(
            future: recentFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    '활동을 불러오지 못했어요.',
                    style: TextStyle(color: DodamHome.inkSoft),
                  ),
                );
              }
              final activities = snapshot.data ?? const <ActivitySummaryDto>[];
              if (snapshot.connectionState == ConnectionState.done &&
                  activities.isEmpty) {
                return const Center(
                  child: Text(
                    '아직 활동 기록이 없어요.',
                    style: TextStyle(color: DodamHome.inkSoft),
                  ),
                );
              }
              return ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: activities.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: DodamHome.line),
                itemBuilder: (context, i) =>
                    _ActivityRow(activity: activities[i]),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});
  final ActivitySummaryDto activity;

  @override
  Widget build(BuildContext context) {
    final status = _statusOf(activity);
    return InkWell(
      onTap: () => AppNavigation.pushNamed(
        context,
        AppRoutes.activityDetail(activity.activityId.toString()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: DodamHome.warm,
                border: Border.all(color: DodamHome.line),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.draw_outlined,
                size: 24,
                color: DodamHome.inkSoft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title ?? activity.drawingType.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DodamHome.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${_dateOf(activity.startedAt)} · ${activity.drawingType.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: DodamHome.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _StatusBadge(status: status),
          ],
        ),
      ),
    );
  }

  static _Status _statusOf(ActivitySummaryDto a) {
    if (a.sessionStatus == 'FAILED' || a.analysisStatus == 'FAILED') {
      return _Status.fail;
    }
    if (a.analysisStatus == 'SUCCESS' ||
        a.analysisStatus == 'COMPLETED' ||
        a.sessionStatus == 'COMPLETED') {
      return _Status.done;
    }
    return _Status.ing;
  }

  static String _dateOf(String iso) {
    final at = DateTime.tryParse(iso)?.toLocal();
    if (at == null) return iso;
    return '${at.month}월 ${at.day}일';
  }
}

enum _Status { ing, done, fail }

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final _Status status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      _Status.ing => ('분석중', DodamHome.blueSoft, DodamHome.blue),
      _Status.done => ('완료', DodamHome.greenSoft, DodamHome.green),
      _Status.fail => ('실패', DodamHome.coralSoft, DodamHome.coral),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
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
    if (id == null || repo == null) return const _Card(child: SizedBox());
    return MindCalendarCard(
      key: ValueKey('mind-calendar-$id'),
      childId: id,
      childName: childName,
      repository: repo,
    );
  }
}
