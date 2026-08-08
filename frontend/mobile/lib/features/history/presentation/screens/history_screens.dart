import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/state/guardian_child_controller.dart';
import '../../../../app/widgets/app_failure_view.dart';
import '../../../../core/domain/report_status.dart';
import '../../../../design_system/design_system.dart';
import '../../../activity/data/dto/activity_dtos.dart';
import '../../../activity/domain/models/activity_conversation_turn.dart';
import '../../../activity/domain/repositories/activity_repository.dart';
import '../../../child/data/dto/child_dtos.dart';
import '../../../conversation/conversation.dart';

enum _HistoryStatus { loading, success, empty, error, noChild }

enum _PeriodFilter { all, recent30Days }

enum _StatusFilter { all, done, analyzing, failed }

enum _CardStatus { done, analyzing, failed, draft }

/// 활동 기록 화면 안에서만 사용하는 기록 보관소 팔레트.
///
/// 공통 디자인 토큰을 바꾸지 않고, 양피지·월넛·황동의 따뜻한 인상을 이 화면에만
/// 제한한다. 상태색과 공통 CTA는 기존 [AppColors] 계약을 그대로 사용한다.
abstract final class _ArchiveColors {
  static const forest = Color(0xFF214A38);
  static const forestDeep = Color(0xFF163428);
  static const forestSoft = Color(0xFFE5EEE7);
  static const walnut = Color(0xFF70462D);
  static const walnutSoft = Color(0xFFE8D6BE);
  static const brass = Color(0xFF9A6C1F);
  static const brassSoft = Color(0xFFF3E4B9);
  static const parchment = Color(0xFFFFF9E9);
  static const parchmentDeep = Color(0xFFF6EBCF);
  static const parchmentLine = Color(0xFFDCC99E);

  // 설정 화면의 `_ForgePalette`와 같은 재료감을 공유하는 배너 전용 색상.
  // 목록·필터·카드의 기존 기록 보관소 팔레트에는 영향을 주지 않는다.
  static const heroSage = Color(0xFFDDEAD5);
  static const heroForest = Color(0xFF315B49);
  static const heroOutline = Color(0xFFE7D9B8);
  static const heroBrass = Color(0xFFC89B3C);
  static const heroWalnut = Color(0xFF795035);
}

/// 활동 기록 목록·상세 화면(시안). 좌측 목록+필터, 우측 선택 활동 프리뷰.
///
/// 사이드바 '기록' 탭에선 [embedded]로 자체 헤더/뒤로가기 없이 콘텐츠만 그려
/// 셸 크롬과 겹치지 않는다. 단독 라우트에선 Scaffold와 뒤로가기를 제공한다.
class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({
    required this.childController,
    required this.repository,
    this.embedded = false,
    super.key,
  });

  final GuardianChildController childController;
  final ActivityRepository repository;
  final bool embedded;

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  _HistoryStatus _status = _HistoryStatus.loading;
  Object? _failure;
  List<ActivitySummaryDto> _activities = const [];
  List<ActivityDrawingTypeDto> _knownTypes = const [];
  int _totalActivityCount = 0;
  int? _selectedActivityId;
  String? _drawingType;
  _PeriodFilter _period = _PeriodFilter.all;
  _StatusFilter _statusFilter = _StatusFilter.all;

  /// 마지막으로 불러온 아동. 컨트롤러는 여러 이유로 알림을 보내므로,
  /// 대상 아동이 실제로 바뀐 경우에만 다시 조회한다.
  int? _loadedChildId;

  // ── 무한 스크롤(페이지네이션) 상태 (S15P11B209-513) ──────────────────
  final ScrollController _scrollController = ScrollController();

  /// 마지막으로 불러온 페이지 번호(0부터). 다음은 `_page + 1`.
  int _page = 0;

  /// 서버에 아직 더 불러올 페이지가 있는지.
  bool _hasNext = false;

  /// 다음 페이지를 불러오는 중인지(중복 요청 방지·하단 로더 표시).
  bool _loadingMore = false;

  /// 다음 페이지 로드가 실패했을 때의 오류. 하단 재시도 버튼을 띄운다.
  Object? _loadMoreFailed;

  /// 조회 세대. 필터·아동이 바뀌면 증가시켜, 진행 중이던 이전 조회의 응답을
  /// 무시한다(늦게 도착한 응답이 새 목록을 덮어쓰지 못하게).
  int _loadGeneration = 0;

  /// 목록이 화면을 못 채워 스크롤이 안 생길 때 자동으로 더 당길 수 있는 횟수.
  /// 무한 반복을 막는 예산이며 [_load]마다 초기화한다.
  int _autoFillBudget = _autoFillBudgetMax;

  /// 목록 끝에서 이 거리(px) 안으로 들어오면 다음 페이지를 미리 당긴다.
  static const double _loadMoreThreshold = 400;
  static const int _autoFillBudgetMax = 5;

  /// 상태 필터(클라이언트)를 적용한 보이는 목록.
  List<ActivitySummaryDto> get _visible => _statusFilter == _StatusFilter.all
      ? _activities
      : _activities
            .where((a) => _cardStatus(a) == _cardStatusOf(_statusFilter))
            .toList(growable: false);

  ActivitySummaryDto? get _selectedActivity {
    final visible = _visible;
    for (final activity in visible) {
      if (activity.activityId == _selectedActivityId) return activity;
    }
    return visible.firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    // 탭의 뿌리로 살아 있는 동안 보호자가 아이를 바꿀 수 있다.
    widget.childController.addListener(_onChildChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    widget.childController.removeListener(_onChildChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onChildChanged() {
    if (widget.childController.selectedChildId == _loadedChildId) return;
    unawaited(_load());
  }

  /// 첫 페이지를 새로 불러온다. 아동·필터가 바뀌는 리셋 지점이므로 페이지 상태도
  /// 처음으로 되돌린다. 늦게 도착한 이전 조회 응답은 세대(generation)로 걸러낸다.
  Future<void> _load() async {
    final childId = widget.childController.selectedChildId;
    _loadedChildId = childId;
    final generation = ++_loadGeneration;
    if (childId == null) {
      setState(() {
        _status = _HistoryStatus.noChild;
        _activities = const [];
        _totalActivityCount = 0;
        _selectedActivityId = null;
        _resetPagination();
      });
      return;
    }
    setState(() {
      _status = _HistoryStatus.loading;
      _failure = null;
      _totalActivityCount = 0;
      _resetPagination();
    });
    try {
      final response = await widget.repository.getActivities(
        childId,
        filter: _filterForPage(0),
      );
      if (!mounted || generation != _loadGeneration) return;
      final activities = response.content;
      final selectedStillExists = activities.any(
        (activity) => activity.activityId == _selectedActivityId,
      );
      setState(() {
        _activities = activities;
        _totalActivityCount = response.totalElements;
        _knownTypes = _mergeKnownTypes(const [], activities);
        _page = 0;
        _hasNext = response.hasNext && activities.isNotEmpty;
        _selectedActivityId = selectedStillExists
            ? _selectedActivityId
            : activities.firstOrNull?.activityId;
        _status = activities.isEmpty
            ? _HistoryStatus.empty
            : _HistoryStatus.success;
      });
      _scheduleAutoFill();
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _failure = error;
        _status = _HistoryStatus.error;
      });
    }
  }

  /// 다음 페이지를 불러와 목록 뒤에 이어붙인다(무한 스크롤). 이미 불러오는 중이거나
  /// 다음 페이지가 없거나 목록 상태가 아니면 아무 일도 하지 않는다.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext || _status != _HistoryStatus.success) return;
    final childId = _loadedChildId;
    if (childId == null) return;
    final generation = _loadGeneration;
    final nextPage = _page + 1;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = null;
    });
    try {
      final response = await widget.repository.getActivities(
        childId,
        filter: _filterForPage(nextPage),
      );
      // 도중에 필터·아동이 바뀌었으면(세대 불일치) 이 페이지는 버린다.
      if (!mounted || generation != _loadGeneration) return;
      final existingIds = {for (final a in _activities) a.activityId};
      final fresh = response.content
          .where((activity) => !existingIds.contains(activity.activityId))
          .toList(growable: false);
      setState(() {
        _activities = [..._activities, ...fresh];
        _totalActivityCount = response.totalElements;
        _knownTypes = _mergeKnownTypes(_knownTypes, fresh);
        _page = nextPage;
        // 빈 페이지거나 새로 추가된 게 없으면 끝으로 본다(중복 응답 방어).
        _hasNext = response.hasNext && fresh.isNotEmpty;
        _loadingMore = false;
      });
      if (fresh.isNotEmpty) _scheduleAutoFill();
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = error;
      });
    }
  }

  void _resetPagination() {
    _page = 0;
    _hasNext = false;
    _loadingMore = false;
    _loadMoreFailed = null;
    _autoFillBudget = _autoFillBudgetMax;
  }

  ActivityFilterDto _filterForPage(int page) {
    final now = DateTime.now().toUtc();
    return ActivityFilterDto(
      page: page,
      // HISTORY-01 from/to는 date(yyyy-MM-dd) — datetime을 보내면 서버가
      // 필터를 적용하지 못한다.
      from: _period == _PeriodFilter.recent30Days
          ? _isoDate(now.subtract(const Duration(days: 30)))
          : null,
      to: _period == _PeriodFilter.recent30Days ? _isoDate(now) : null,
      drawingType: _drawingType,
    );
  }

  /// 이미 아는 유형과 새로 들어온 활동의 유형을 code 기준으로 합친다(중복 제거).
  List<ActivityDrawingTypeDto> _mergeKnownTypes(
    List<ActivityDrawingTypeDto> base,
    List<ActivitySummaryDto> activities,
  ) => <String, ActivityDrawingTypeDto>{
    for (final type in base) type.code: type,
    for (final activity in activities)
      activity.drawingType.code: activity.drawingType,
  }.values.toList(growable: false);

  /// 목록 끝 근처로 스크롤하면 다음 페이지를 미리 당긴다.
  void _onScroll() {
    if (!_scrollController.hasClients ||
        !_hasNext ||
        _loadingMore ||
        _loadMoreFailed != null) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      unawaited(_loadMore());
    }
  }

  /// 방금 불러온 페이지가 화면을 다 못 채워 스크롤이 생기지 않으면(예: 상태 필터로
  /// 보이는 항목이 적을 때) 다음 페이지를 한 번 더 당겨 스크롤로 이어볼 수 있게 한다.
  /// [_autoFillBudget]으로 무한 반복을 막는다.
  void _scheduleAutoFill() {
    if (!_hasNext || _autoFillBudget <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_hasNext ||
          _loadingMore ||
          _loadMoreFailed != null ||
          !_scrollController.hasClients) {
        return;
      }
      if (_scrollController.position.maxScrollExtent <= 0) {
        _autoFillBudget -= 1;
        unawaited(_loadMore());
      }
    });
  }

  /// 목록 하단에 붙일 로더/재시도 조각. 없으면 null.
  Widget? _loadMoreFooter() {
    if (_loadingMore) {
      return const Padding(
        key: ValueKey('activity-history-load-more'),
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (_loadMoreFailed != null) {
      return Padding(
        key: const ValueKey('activity-history-load-more-error'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(
          child: AppButton(
            label: '더 불러오기',
            variant: AppButtonVariant.secondary,
            expand: false,
            leading: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _loadMoreFailed = null);
              unawaited(_loadMore());
            },
          ),
        ),
      );
    }
    return null;
  }

  Future<void> _selectChild(int childId) async {
    final child = widget.childController.children
        .where((item) => item.childId == childId)
        .firstOrNull;
    if (child == null) return;
    widget.childController.selectChild(child);
    _drawingType = null;
    _statusFilter = _StatusFilter.all;
    _selectedActivityId = null;
    await _load();
  }

  void _openReport(ActivitySummaryDto activity) {
    final report = activity.report;
    if (report == null) return;
    AppNavigation.pushNamed(
      context,
      AppRoutes.report(report.reportId.toString()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(top: false, child: _content(context));
    return widget.embedded
        ? ColoredBox(color: AppColors.canvas, child: content)
        : Scaffold(backgroundColor: AppColors.canvas, body: content);
  }

  // 넓은 태블릿에서 콘텐츠가 화면 끝까지 늘어나지 않도록 폭 상한 적용(홈·리포트와 일관,
  // S15P11B209-787). 좁은 폭에선 무시돼 개편 레이아웃을 그대로 쓴다.
  Widget _content(BuildContext context) => ResponsiveContent(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final showFilters =
            _status != _HistoryStatus.noChild &&
            _status != _HistoryStatus.loading;
        final hero = _ArchiveHero(
          embedded: widget.embedded,
          activityCount: _totalActivityCount,
          showCount:
              _status == _HistoryStatus.success ||
              _status == _HistoryStatus.empty,
          onBack: () => Navigator.of(context).maybePop(),
        );
        final padding = EdgeInsets.fromLTRB(
          compact ? AppSpacing.md : AppSpacing.lg,
          AppSpacing.md,
          compact ? AppSpacing.md : AppSpacing.lg,
          compact ? AppSpacing.md : AppSpacing.lg,
        );
        if (constraints.maxHeight < 520) {
          return Padding(
            padding: padding,
            child: ListView(
              key: const ValueKey('activity-history-low-height-layout'),
              children: [
                hero,
                if (showFilters) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _buildFilters(),
                ],
                const SizedBox(height: AppSpacing.sm),
                SizedBox(height: constraints.maxHeight, child: _buildBody()),
              ],
            ),
          );
        }
        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hero,
              if (showFilters) ...[
                const SizedBox(height: AppSpacing.sm),
                _buildFilters(),
                const SizedBox(height: AppSpacing.sm),
              ] else
                const SizedBox(height: AppSpacing.sm),
              Expanded(child: _buildBody()),
            ],
          ),
        );
      },
    ),
  );

  Widget _buildFilters() => _ActivityFilters(
    children: widget.childController.children,
    selectedChildId: widget.childController.selectedChildId,
    period: _period,
    drawingType: _drawingType,
    drawingTypes: _knownTypes,
    statusFilter: _statusFilter,
    onChildChanged: _selectChild,
    onPeriodChanged: (value) {
      setState(() => _period = value);
      _load();
    },
    onDrawingTypeChanged: (value) {
      setState(() => _drawingType = value);
      _load();
    },
    onStatusChanged: (value) => setState(() {
      _statusFilter = value;
      _selectedActivityId = _selectedActivity?.activityId;
    }),
  );

  Widget _buildBody() => switch (_status) {
    _HistoryStatus.loading => const AppLoadingView(
      key: ValueKey('activity-history-loading'),
      message: '활동 기록을 불러오고 있어요',
    ),
    _HistoryStatus.noChild => const AppEmptyView(
      key: ValueKey('activity-history-no-child'),
      title: '확인할 아이를 먼저 선택해 주세요',
      message: '보호자 홈에서 아이를 선택하면 활동 기록을 볼 수 있어요.',
    ),
    _HistoryStatus.empty => const AppEmptyView(
      key: ValueKey('activity-history-empty'),
      title: '아직 활동 기록이 없어요',
      message: '그림 활동을 마치면 이곳에서 기록을 확인할 수 있어요.',
    ),
    _HistoryStatus.error => AppFailureView(
      key: const ValueKey('activity-history-error'),
      title: '활동 기록을 불러오지 못했어요',
      failure: _failure,
      onRetry: _load,
    ),
    _HistoryStatus.success => LayoutBuilder(
      builder: (context, constraints) {
        Widget list({bool scrollable = true}) => _ActivityListView(
          activities: _visible,
          selectedActivityId: _selectedActivity?.activityId,
          repository: widget.repository,
          scrollable: scrollable,
          // 스크롤러가 되는 리스트에만 컨트롤러를 붙인다. 좁은 화면에선 바깥
          // ListView가 스크롤러라 여기(scrollable=false)엔 붙이지 않는다.
          controller: scrollable ? _scrollController : null,
          footer: _loadMoreFooter(),
          onSelected: (activityId) =>
              setState(() => _selectedActivityId = activityId),
          onReport: _openReport,
        );
        final selectedChildName = widget.childController.children
            .where(
              (child) =>
                  child.childId == widget.childController.selectedChildId,
            )
            .firstOrNull
            ?.nickname;
        final preview = _PreviewPane(
          activity: _selectedActivity,
          childName: selectedChildName,
          repository: widget.repository,
          onReport: _openReport,
        );
        if (constraints.maxWidth < 780) {
          return ListView(
            key: const ValueKey('activity-history-small-layout'),
            // 좁은 화면에선 이 바깥 ListView가 스크롤러다. 무한 스크롤 감지를
            // 위해 컨트롤러를 여기에 붙인다(안쪽 리스트는 스크롤하지 않는다).
            controller: _scrollController,
            children: [
              list(scrollable: false),
              const SizedBox(height: AppSpacing.lg),
              preview,
              const SizedBox(height: AppSpacing.md),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: list()),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                key: const ValueKey('activity-history-preview-scroll'),
                child: preview,
              ),
            ),
          ],
        );
      },
    ),
  };
}

class _ArchiveHero extends StatelessWidget {
  const _ArchiveHero({
    required this.embedded,
    required this.activityCount,
    required this.showCount,
    required this.onBack,
  });

  final bool embedded;
  final int activityCount;
  final bool showCount;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 700;
      final characterFrameSize = compact
          ? (constraints.maxWidth * 0.29).clamp(92.0, 112.0).toDouble()
          : (constraints.maxWidth * 0.18).clamp(150.0, 176.0).toDouble();
      final count = Semantics(
        label: '총 활동 기록 $activityCount개',
        child: Container(
          key: const ValueKey('activity-history-count'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _ArchiveColors.brassSoft,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: _ArchiveColors.brass),
          ),
          child: Text(
            '$activityCount개의 기록',
            style: const TextStyle(
              color: _ArchiveColors.heroForest,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
      return Container(
        key: const ValueKey('activity-history-archive-hero'),
        padding: EdgeInsets.fromLTRB(
          embedded ? AppSpacing.md : AppSpacing.xxl,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _ArchiveColors.heroSage,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: _ArchiveColors.heroOutline),
        ),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            if (!compact)
              const Positioned(
                right: AppSpacing.sm,
                bottom: 0,
                child: _ArchiveBooksPattern(),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 1,
                color: _ArchiveColors.heroBrass.withValues(alpha: 0.72),
              ),
            ),
            if (!embedded)
              Positioned(
                left: -AppSpacing.xs,
                top: 0,
                child: IconButton(
                  key: const ValueKey('activity-history-back'),
                  onPressed: onBack,
                  tooltip: '뒤로 가기',
                  color: _ArchiveColors.heroForest,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!embedded) const SizedBox(width: AppSpacing.xl),
                _ScribeFrame(size: characterFrameSize),
                SizedBox(width: compact ? AppSpacing.sm : AppSpacing.lg),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '보호자 활동 기록',
                        key: ValueKey('activity-history-eyebrow'),
                        style: TextStyle(
                          color: _ArchiveColors.heroForest,
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: compact ? 3 : AppSpacing.xs),
                      Semantics(
                        header: true,
                        child: Text(
                          // 셸 탭(`embedded`)에는 상단 페이지 타이틀 "활동 기록"이
                          // 이미 있으므로 배너 큰 제목은 설정·알림 탭처럼 서술형으로
                          // 둔다. 단독 라우트에는 그 타이틀이 없어 배너가 화면
                          // 이름을 대신 말해야 한다(S15P11B209-948).
                          embedded ? '기록을 한 권씩 살펴봐요' : '활동 기록',
                          style: TextStyle(
                            color: _ArchiveColors.heroForest,
                            fontSize: compact ? 23 : 27,
                            height: 1.2,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 3 : AppSpacing.xs),
                      const Text(
                        '아이의 그림과 이야기를 한 권씩 소중히 모았어요.',
                        style: TextStyle(
                          color: _ArchiveColors.heroForest,
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (compact && showCount) ...[
                        const SizedBox(height: AppSpacing.sm),
                        count,
                      ],
                    ],
                  ),
                ),
                if (!compact && showCount) ...[
                  const SizedBox(width: AppSpacing.md),
                  count,
                ],
              ],
            ),
          ],
        ),
      );
    },
  );
}

// ── 필터 ─────────────────────────────────────────────────────────────
class _ScribeFrame extends StatelessWidget {
  const _ScribeFrame({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('activity-history-scribe-frame'),
    width: size,
    height: size,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: _ArchiveColors.parchment,
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: _ArchiveColors.brass, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: _ArchiveColors.walnut.withValues(alpha: 0.42),
          offset: const Offset(0, 5),
          blurRadius: 0,
        ),
      ],
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _ArchiveColors.parchmentDeep,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ArchiveColors.brass.withValues(alpha: 0.58)),
      ),
      child: Padding(
        // 원본 PNG의 투명 여백을 포함해 실제 캐릭터 도형이 프레임의 약 80%를
        // 차지하도록 한다. 원본 비율과 알파 채널은 그대로 유지한다.
        padding: EdgeInsets.all(size * 0.04),
        child: Image.asset(
          'assets/characters/dodami_scribe_profile.png',
          key: const ValueKey('activity-history-scribe'),
          fit: BoxFit.contain,
          semanticLabel: '활동 기록을 정리하는 도담이',
          filterQuality: FilterQuality.high,
        ),
      ),
    ),
  );
}

class _ArchiveBooksPattern extends StatelessWidget {
  const _ArchiveBooksPattern();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Opacity(
        opacity: 0.08,
        child: SizedBox(
          key: const ValueKey('activity-history-books-pattern'),
          width: 224,
          height: 58,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.end,
            children: const [
              _ArchiveBookSpine(width: 28, height: 42, bandOffset: 10),
              _ArchiveBookSpine(width: 34, height: 55, bandOffset: 35),
              _ArchiveBookSpine(width: 25, height: 47, bandOffset: 18),
              _ArchiveBookSpine(width: 31, height: 58, bandOffset: 12),
              _ArchiveBookSpine(width: 27, height: 45, bandOffset: 29),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ArchiveBookSpine extends StatelessWidget {
  const _ArchiveBookSpine({
    required this.width,
    required this.height,
    required this.bandOffset,
  });

  final double width;
  final double height;
  final double bandOffset;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    margin: const EdgeInsets.only(left: 5),
    decoration: BoxDecoration(
      color: _ArchiveColors.heroForest,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      border: Border.all(color: _ArchiveColors.heroWalnut, width: 1.5),
    ),
    child: Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: EdgeInsets.only(top: bandOffset),
        height: 2,
        color: _ArchiveColors.heroBrass,
      ),
    ),
  );
}

class _ActivityFilters extends StatelessWidget {
  const _ActivityFilters({
    required this.children,
    required this.selectedChildId,
    required this.period,
    required this.drawingType,
    required this.drawingTypes,
    required this.statusFilter,
    required this.onChildChanged,
    required this.onPeriodChanged,
    required this.onDrawingTypeChanged,
    required this.onStatusChanged,
  });
  final List<ChildSummaryDto> children;
  final int? selectedChildId;
  final _PeriodFilter period;
  final String? drawingType;
  final List<ActivityDrawingTypeDto> drawingTypes;
  final _StatusFilter statusFilter;
  final ValueChanged<int> onChildChanged;
  final ValueChanged<_PeriodFilter> onPeriodChanged;
  final ValueChanged<String?> onDrawingTypeChanged;
  final ValueChanged<_StatusFilter> onStatusChanged;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('activity-history-filters'),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: _ArchiveColors.parchment,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: _ArchiveColors.parchmentLine),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.sm;
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: width,
              child: _FilterDropdown<int>(
                key: const ValueKey('activity-child-filter'),
                label: '아동',
                value: selectedChildId,
                items: [
                  for (final child in children) (child.childId, child.nickname),
                ],
                onChanged: (value) {
                  if (value != null) onChildChanged(value);
                },
              ),
            ),
            SizedBox(
              width: width,
              child: _FilterDropdown<_PeriodFilter>(
                key: const ValueKey('activity-period-filter'),
                label: '기간',
                value: period,
                items: const [
                  (_PeriodFilter.all, '전체 기간'),
                  (_PeriodFilter.recent30Days, '최근 30일'),
                ],
                onChanged: (value) {
                  if (value != null) onPeriodChanged(value);
                },
              ),
            ),
            SizedBox(
              width: width,
              child: _FilterDropdown<String?>(
                key: const ValueKey('activity-type-filter'),
                label: '유형',
                value: drawingType,
                items: [
                  const (null, '전체 활동'),
                  for (final type in drawingTypes) (type.code, type.name),
                ],
                onChanged: onDrawingTypeChanged,
              ),
            ),
            SizedBox(
              width: width,
              child: _FilterDropdown<_StatusFilter>(
                key: const ValueKey('activity-status-filter'),
                label: '상태',
                value: statusFilter,
                items: const [
                  (_StatusFilter.all, '전체 상태'),
                  (_StatusFilter.done, '분석 완료'),
                  (_StatusFilter.analyzing, '분석 중'),
                  (_StatusFilter.failed, '분석 실패'),
                ],
                onChanged: (value) {
                  if (value != null) onStatusChanged(value);
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });
  final String label;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) {
    final selectedLabel = items
        .where((item) => item.$1 == value)
        .firstOrNull
        ?.$2;
    return Semantics(
      key: ValueKey('activity-filter-semantics-$label'),
      container: true,
      label: '$label 필터, 현재 ${selectedLabel ?? '선택 안 됨'}',
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: _ArchiveColors.forest,
            fontWeight: FontWeight.w700,
          ),
          floatingLabelStyle: const TextStyle(
            color: _ArchiveColors.forestDeep,
            fontWeight: FontWeight.w800,
          ),
          filled: true,
          fillColor: _ArchiveColors.parchmentDeep,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: _ArchiveColors.parchmentLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(
              color: _ArchiveColors.forest,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),
        selectedItemBuilder: (context) => [
          for (final item in items)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
        items: [
          for (final item in items)
            DropdownMenuItem<T>(
              value: item.$1,
              child: Text(item.$2, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

// ── 목록 ─────────────────────────────────────────────────────────────
class _ActivityListView extends StatelessWidget {
  const _ActivityListView({
    required this.activities,
    required this.selectedActivityId,
    required this.repository,
    required this.onSelected,
    required this.onReport,
    this.scrollable = true,
    this.controller,
    this.footer,
  });
  final List<ActivitySummaryDto> activities;
  final int? selectedActivityId;
  final ActivityRepository repository;
  final ValueChanged<int> onSelected;
  final ValueChanged<ActivitySummaryDto> onReport;
  final bool scrollable;

  /// 스크롤러일 때만 붙는 컨트롤러(무한 스크롤 감지용).
  final ScrollController? controller;

  /// 목록 하단에 덧붙일 조각(다음 페이지 로더/재시도). 없으면 붙이지 않는다.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return const AppEmptyView(
        key: ValueKey('activity-history-filtered-empty'),
        title: '조건에 맞는 활동이 없어요',
        message: '필터를 바꿔 다시 확인해 보세요.',
      );
    }
    final hasFooter = footer != null;
    final list = ListView.separated(
      key: const ValueKey('activity-history-list'),
      controller: scrollable ? controller : null,
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: activities.length + (hasFooter ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index >= activities.length) return footer!;
        final activity = activities[index];
        return _ActivityCard(
          activity: activity,
          selected: activity.activityId == selectedActivityId,
          repository: repository,
          onTap: () => onSelected(activity.activityId),
          onReport: () => onReport(activity),
        );
      },
    );
    return Column(
      mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ArchiveSectionTitle(
          icon: Icons.auto_stories_outlined,
          title: '기록 서가',
        ),
        const SizedBox(height: AppSpacing.sm),
        if (scrollable) Expanded(child: list) else list,
      ],
    );
  }
}

class _ArchiveSectionTitle extends StatelessWidget {
  const _ArchiveSectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: _ArchiveColors.brass, size: 22),
      const SizedBox(width: AppSpacing.xs),
      Text(
        title,
        style: const TextStyle(
          color: _ArchiveColors.forestDeep,
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      const Expanded(child: Divider(color: _ArchiveColors.parchmentLine)),
    ],
  );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.activity,
    required this.selected,
    required this.repository,
    required this.onTap,
    required this.onReport,
  });
  final ActivitySummaryDto activity;
  final bool selected;
  final ActivityRepository repository;
  final VoidCallback onTap;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final status = _cardStatus(activity);
    final title = activity.title ?? activity.drawingType.name;
    final reportReady = _reportReady(activity);
    final semanticLabel = [
      title,
      _date(activity.completedAt ?? activity.startedAt),
      _inputLabel(activity.inputMethod),
      _cardStatusLabel(status),
      activity.drawingType.name,
    ].join(', ');
    return Semantics(
      key: ValueKey('activity-semantics-${activity.activityId}'),
      container: true,
      explicitChildNodes: true,
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: selected
            ? _ArchiveColors.parchmentDeep
            : _ArchiveColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          key: ValueKey('activity-${activity.activityId}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: selected
                    ? _ArchiveColors.forest
                    : _ArchiveColors.parchmentLine,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 9,
                  child: ColoredBox(
                    key: ValueKey('activity-spine-${activity.activityId}'),
                    color: _spineColor(activity),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md + 9,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 500;
                      final details = Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _Thumbnail(
                            url: activity.thumbnailUrl,
                            repository: repository,
                            size: compact ? 52 : 60,
                            semanticLabel: '$title 활동 그림',
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _ArchiveColors.forestDeep,
                                          fontSize: 15,
                                          height: 1.25,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    if (selected) ...[
                                      const SizedBox(width: AppSpacing.xs),
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        key: ValueKey(
                                          'activity-selected-indicator',
                                        ),
                                        color: _ArchiveColors.forest,
                                        size: 22,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${_date(activity.completedAt ?? activity.startedAt)} · '
                                  '${_inputLabel(activity.inputMethod)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.inkMuted,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Wrap(
                                  spacing: AppSpacing.xs,
                                  runSpacing: AppSpacing.xs,
                                  children: [
                                    _StatusBadge(status: status),
                                    _TypeBadge(name: activity.drawingType.name),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      if (compact && reportReady) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            details,
                            const SizedBox(height: AppSpacing.sm),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _CardAction(onReport: onReport),
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: details),
                          if (reportReady) ...[
                            const SizedBox(width: AppSpacing.sm),
                            _CardAction(onReport: onReport),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({required this.onReport});
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onReport,
    style: TextButton.styleFrom(
      foregroundColor: _ArchiveColors.forestDeep,
      backgroundColor: _ArchiveColors.forestSoft,
      minimumSize: const Size(AppSizes.minTouchTarget, AppSizes.minTouchTarget),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: _ArchiveColors.forest),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    ),
    icon: const Icon(Icons.description_outlined, size: 18),
    label: const Text(
      '리포트',
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    ),
  );
}

// ── 우측 프리뷰(그림 + 관찰 리포트 보기) ─────────────────────────────
class _PreviewPane extends StatefulWidget {
  const _PreviewPane({
    required this.activity,
    required this.childName,
    required this.repository,
    required this.onReport,
  });
  final ActivitySummaryDto? activity;
  final String? childName;
  final ActivityRepository repository;
  final ValueChanged<ActivitySummaryDto> onReport;

  @override
  State<_PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<_PreviewPane> {
  int _drawingIndex = 0;

  @override
  void didUpdateWidget(covariant _PreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity?.activityId != widget.activity?.activityId) {
      _drawingIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    final htpDrawings = activity?.htpDrawings ?? const [];
    final hasHtpCarousel = activity?.isHtp == true && htpDrawings.isNotEmpty;
    final safeIndex = hasHtpCarousel
        ? _drawingIndex.clamp(0, htpDrawings.length - 1)
        : 0;
    final selectedHtpDrawing = hasHtpCarousel ? htpDrawings[safeIndex] : null;
    final title = activity?.title ?? activity?.drawingType.name;
    final stageLabel = selectedHtpDrawing == null
        ? null
        : _htpSubjectLabel(selectedHtpDrawing.drawingSubject);
    final imageLabel = activity == null
        ? null
        : '${widget.childName ?? '아이'}의 $title${stageLabel == null ? '' : ' $stageLabel'} 그림';
    return Container(
      key: const ValueKey('activity-history-summary'),
      decoration: BoxDecoration(
        color: _ArchiveColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: _ArchiveColors.walnut, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: activity == null
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: AppEmptyView(title: '활동을 선택해 주세요'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 히어로 배너와 같은 세이지+짙은 초록 조합을 쓴다. 배너는 밝고
                // 이 헤더만 짙은 초록이라 같은 화면에서 두 결이 부딪혔다
                // (S15P11B209-948). 대비는 배너에서 이미 AA를 넘긴 짝이다.
                Container(
                  color: _ArchiveColors.heroSage,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.menu_book_rounded,
                        color: _ArchiveColors.heroWalnut,
                        size: 28,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '펼친 기록서',
                              style: TextStyle(
                                color: _ArchiveColors.heroForest,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ArchiveColors.heroForest,
                                fontSize: 20,
                                height: 1.25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _ArchiveSectionTitle(
                        icon: Icons.history_edu_rounded,
                        title: '아이의 그림',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        key: const ValueKey('activity-history-open-page'),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDF5),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: _ArchiveColors.parchmentLine,
                          ),
                        ),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: _Thumbnail(
                                  url:
                                      selectedHtpDrawing?.thumbnailUrl ??
                                      activity.thumbnailUrl,
                                  repository: widget.repository,
                                  fit: BoxFit.contain,
                                  semanticLabel: imageLabel,
                                ),
                              ),
                              if (hasHtpCarousel) ...[
                                Positioned(
                                  left: AppSpacing.xs,
                                  child: _CarouselButton(
                                    key: const ValueKey('htp-preview-previous'),
                                    icon: Icons.chevron_left_rounded,
                                    enabled: safeIndex > 0,
                                    onPressed: () {
                                      setState(
                                        () => _drawingIndex = safeIndex - 1,
                                      );
                                    },
                                  ),
                                ),
                                Positioned(
                                  right: AppSpacing.xs,
                                  child: _CarouselButton(
                                    key: const ValueKey('htp-preview-next'),
                                    icon: Icons.chevron_right_rounded,
                                    enabled: safeIndex < htpDrawings.length - 1,
                                    onPressed: () {
                                      setState(
                                        () => _drawingIndex = safeIndex + 1,
                                      );
                                    },
                                  ),
                                ),
                                Positioned(
                                  bottom: AppSpacing.xs,
                                  child: Container(
                                    key: const ValueKey(
                                      'htp-preview-indicator',
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _ArchiveColors.forestDeep
                                          .withValues(alpha: 0.88),
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.pill,
                                      ),
                                    ),
                                    child: Text(
                                      '$stageLabel ${safeIndex + 1}/${htpDrawings.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          _StatusBadge(status: _cardStatus(activity)),
                          _TypeBadge(name: activity.drawingType.name),
                          _Pill(
                            label: _date(
                              activity.completedAt ?? activity.startedAt,
                            ),
                            fg: _ArchiveColors.walnut,
                            bg: _ArchiveColors.walnutSoft,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        key: const ValueKey('activity-report-cta'),
                        label: '관찰 리포트 보기',
                        leading: const Icon(Icons.description_outlined),
                        onPressed: _reportReady(activity)
                            ? () => widget.onReport(activity)
                            : null,
                      ),
                      if (!_reportReady(activity)) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _reportUnavailableMessage(activity),
                          key: const ValueKey(
                            'activity-report-unavailable-reason',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CarouselButton extends StatelessWidget {
  const _CarouselButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = icon == Icons.chevron_left_rounded ? '이전 그림' : '다음 그림';
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: AppColors.surface.withValues(alpha: 0.92),
          shape: const CircleBorder(),
          elevation: enabled ? 2 : 0,
          child: IconButton(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon),
            color: AppColors.ink,
            disabledColor: AppColors.outline,
            tooltip: label,
          ),
        ),
      ),
    );
  }
}

String _htpSubjectLabel(String subject) => switch (subject) {
  'HOUSE' => '집',
  'TREE' => '나무',
  'PERSON' => '사람',
  _ => subject,
};

// ── 배지 ─────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final _CardStatus status;
  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      _CardStatus.done => ('분석 완료', AppColors.success, AppColors.successSoft),
      _CardStatus.analyzing => (
        '분석 중',
        AppColors.lavender,
        AppColors.lavenderSoft,
      ),
      _CardStatus.failed => ('분석 실패', AppColors.error, AppColors.errorSoft),
      _CardStatus.draft => ('임시 저장', AppColors.warning, AppColors.warningSoft),
    };
    return _Pill(label: label, fg: fg, bg: bg);
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) =>
      _Pill(label: name, fg: AppColors.inkMuted, bg: AppColors.surfaceSoft);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.fg, required this.bg});
  final String label;
  final Color fg, bg;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.url,
    required this.repository,
    this.size,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });
  final String? url;
  final ActivityRepository repository;
  final double? size;
  final BoxFit fit;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final image = AuthenticatedImage(
      url: url,
      fetcher: repository.downloadImage,
      fit: fit,
      semanticLabel: semanticLabel,
      placeholderBuilder: (_) => Container(
        key: const ValueKey('activity-thumbnail-placeholder'),
        color: AppColors.surfaceSoft,
        alignment: Alignment.center,
        child: Semantics(
          image: semanticLabel != null,
          label: semanticLabel,
          child: const Icon(Icons.image_outlined, color: AppColors.inkMuted),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: size == null
          ? image
          : SizedBox(width: size, height: size, child: image),
    );
  }
}

/// 관찰 리포트로 진입 가능한지(완료된 리포트가 있는지).
bool _reportReady(ActivitySummaryDto activity) {
  final report = activity.report;
  return report != null && report.reportStatus == 'COMPLETED';
}

String _reportUnavailableMessage(ActivitySummaryDto activity) =>
    switch (_cardStatus(activity)) {
      _CardStatus.analyzing => '분석이 끝나면 관찰 리포트를 확인할 수 있어요.',
      _CardStatus.failed => '분석을 완료하지 못해 리포트를 열 수 없어요.',
      _CardStatus.draft => '활동을 마치면 관찰 리포트를 확인할 수 있어요.',
      _CardStatus.done => '아직 연결된 관찰 리포트가 없어요.',
    };

String _cardStatusLabel(_CardStatus status) => switch (status) {
  _CardStatus.done => '분석 완료',
  _CardStatus.analyzing => '분석 중',
  _CardStatus.failed => '분석 실패',
  _CardStatus.draft => '임시 저장',
};

Color _spineColor(ActivitySummaryDto activity) {
  if (activity.isHtp) return _ArchiveColors.walnut;
  return switch (activity.drawingType.code) {
    'ART_DIARY' => _ArchiveColors.brass,
    'FREE_DRAWING' => _ArchiveColors.forest,
    _ => _ArchiveColors.walnut,
  };
}

_CardStatus _cardStatus(ActivitySummaryDto activity) {
  if (activity.sessionStatus == 'DRAFT') return _CardStatus.draft;
  final reportStatus = activity.report?.reportStatus;
  if (activity.analysisStatus == 'FAILED' ||
      isReportFailureVisibleToGuardian(reportStatus)) {
    return _CardStatus.failed;
  }
  if (reportStatus == 'COMPLETED' ||
      activity.analysisStatus == 'COMPLETED' ||
      activity.analysisStatus == 'SUCCESS') {
    return _CardStatus.done;
  }
  return _CardStatus.analyzing;
}

_CardStatus _cardStatusOf(_StatusFilter filter) => switch (filter) {
  _StatusFilter.done => _CardStatus.done,
  _StatusFilter.analyzing => _CardStatus.analyzing,
  _StatusFilter.failed => _CardStatus.failed,
  _StatusFilter.all => _CardStatus.done,
};

String _inputLabel(String inputMethod) => switch (inputMethod) {
  'CANVAS' => '캔버스',
  'UPLOAD' || 'PHOTO' || 'IMAGE' => '사진 업로드',
  'AUTO_SAVE' || 'DRAFT' => '자동 임시 저장',
  _ => inputMethod,
};

String _date(String isoDate) => isoDate.length >= 10
    ? isoDate.substring(0, 10).replaceAll('-', '.')
    : isoDate;

/// yyyy-MM-dd (HISTORY-01 from/to 파라미터용 date).
String _isoDate(DateTime value) => value.toIso8601String().substring(0, 10);

enum _DetailStatus { loading, success, empty, error, invalidId }

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({
    required this.activityId,
    required this.repository,
    this.voiceAnswerPlaybackRepository,
    this.voiceAnswerAudioPlayerFactory,
    super.key,
  });

  final String activityId;
  final ActivityRepository repository;
  final VoiceAnswerPlaybackRepository? voiceAnswerPlaybackRepository;
  final VoiceAnswerAudioPlayerFactory? voiceAnswerAudioPlayerFactory;

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  _DetailStatus _status = _DetailStatus.loading;
  ActivityDetailDto? _activity;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final activityId = int.tryParse(widget.activityId);
    if (activityId == null || activityId <= 0) {
      setState(() => _status = _DetailStatus.invalidId);
      return;
    }
    setState(() {
      _status = _DetailStatus.loading;
      _failure = null;
    });
    try {
      final activity = await widget.repository.getActivity(activityId);
      if (!mounted) return;
      setState(() {
        _activity = activity.activityId == activityId ? activity : null;
        _status = _activity == null
            ? _DetailStatus.empty
            : _DetailStatus.success;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _status = _DetailStatus.error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '활동 상세',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(top: false, child: _body()),
  );

  Widget _body() => switch (_status) {
    _DetailStatus.loading => const AppLoadingView(
      key: ValueKey('activity-detail-loading'),
      message: '활동 상세를 불러오고 있어요',
    ),
    _DetailStatus.error => AppFailureView(
      key: const ValueKey('activity-detail-error'),
      title: '활동 상세를 불러오지 못했어요',
      failure: _failure,
      onRetry: _load,
    ),
    _DetailStatus.invalidId => const AppErrorView(
      key: ValueKey('activity-detail-invalid-id'),
      title: '활동 정보가 올바르지 않아요',
      message: '활동 이력에서 다시 선택해 주세요.',
    ),
    _DetailStatus.empty => const AppEmptyView(
      key: ValueKey('activity-detail-empty'),
      title: '활동 상세 정보가 없어요',
      message: '이력 목록으로 돌아가 다른 활동을 선택해 주세요.',
    ),
    _DetailStatus.success => _ActivityDetailContent(
      activity: _activity!,
      repository: widget.repository,
      voiceAnswerPlaybackRepository: widget.voiceAnswerPlaybackRepository,
      voiceAnswerAudioPlayerFactory: widget.voiceAnswerAudioPlayerFactory,
    ),
  };
}

class _ActivityDetailContent extends StatelessWidget {
  const _ActivityDetailContent({
    required this.activity,
    required this.repository,
    required this.voiceAnswerPlaybackRepository,
    required this.voiceAnswerAudioPlayerFactory,
  });
  final ActivityDetailDto activity;
  final ActivityRepository repository;
  final VoiceAnswerPlaybackRepository? voiceAnswerPlaybackRepository;
  final VoiceAnswerAudioPlayerFactory? voiceAnswerAudioPlayerFactory;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final left = _ActivityArtwork(activity: activity, repository: repository);
      final right = _ActivityInformation(
        activity: activity,
        repository: repository,
        voiceAnswerPlaybackRepository: voiceAnswerPlaybackRepository,
        voiceAnswerAudioPlayerFactory: voiceAnswerAudioPlayerFactory,
      );
      return SingleChildScrollView(
        key: ValueKey(
          constraints.maxWidth >= 900
              ? 'activity-detail-wide-layout'
              : 'activity-detail-small-layout',
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: constraints.maxWidth >= 900
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: left),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 6, child: right),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  left,
                  const SizedBox(height: AppSpacing.lg),
                  right,
                ],
              ),
      );
    },
  );
}

class _ActivityArtwork extends StatelessWidget {
  const _ActivityArtwork({required this.activity, required this.repository});
  final ActivityDetailDto activity;
  final ActivityRepository repository;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DetailCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activity.title ?? activity.drawingType.name,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_date(activity.completedAt ?? activity.startedAt)} · ${activity.drawingType.name}',
              style: const TextStyle(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          key: const ValueKey('activity-detail-image'),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: AuthenticatedImage(
            url: activity.latestAsset?.fileUrl,
            fetcher: repository.downloadImage,
            fit: BoxFit.contain,
            placeholderBuilder: (_) => const _DetailImagePlaceholder(),
          ),
        ),
      ),
    ],
  );
}

class _ActivityInformation extends StatelessWidget {
  const _ActivityInformation({
    required this.activity,
    required this.repository,
    required this.voiceAnswerPlaybackRepository,
    required this.voiceAnswerAudioPlayerFactory,
  });
  final ActivityDetailDto activity;
  final ActivityRepository repository;
  final VoiceAnswerPlaybackRepository? voiceAnswerPlaybackRepository;
  final VoiceAnswerAudioPlayerFactory? voiceAnswerAudioPlayerFactory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DetailSection(
        title: '활동 정보',
        key: const ValueKey('activity-detail-basic-info'),
        children: [
          _DetailLine(label: '활동 유형', value: activity.drawingType.name),
          _DetailLine(label: '입력 방식', value: activity.inputMethod),
          _DetailLine(label: '진행 상태', value: activity.sessionStatus),
          _DetailLine(label: '현재 단계', value: activity.currentStage),
          _DetailLine(label: '시작', value: _dateTime(activity.startedAt)),
          if (activity.completedAt case final completedAt?)
            _DetailLine(label: '완료', value: _dateTime(completedAt)),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _DetailSection(
        title: '아동이 선택한 감정',
        key: const ValueKey('activity-detail-emotions'),
        children: [
          if (activity.selectedEmotions.isEmpty)
            const Text(
              '선택한 감정 정보가 없어요.',
              style: TextStyle(color: AppColors.inkMuted),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final emotion in activity.selectedEmotions)
                  Chip(label: Text(_emotionLabel(emotion))),
              ],
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _ConversationSection(
        conversationId: activity.conversationId,
        repository: repository,
        voiceAnswerPlaybackRepository: voiceAnswerPlaybackRepository,
        voiceAnswerAudioPlayerFactory: voiceAnswerAudioPlayerFactory,
      ),
      const SizedBox(height: AppSpacing.md),
      _DetailSection(
        title: '분석과 관찰 요약',
        key: const ValueKey('activity-detail-analysis'),
        children: [
          if (activity.latestAnalysis case final analysis?)
            _DetailLine(label: '분석 상태', value: analysis.analysisStatus)
          else
            const Text(
              '아직 생성된 요약이 없어요.',
              style: TextStyle(color: AppColors.inkMuted),
            ),
        ],
      ),
      if (activity.reportId case final reportId?) ...[
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('activity-report-cta'),
          label: '관찰 리포트 보기',
          onPressed: () => AppNavigation.pushNamed(
            context,
            AppRoutes.report(reportId.toString()),
          ),
        ),
      ],
    ],
  );
}

// ── 그림 · AI 질문 · 아동 답변 상세 ────────────────────────────────────

/// 활동에 연결된 대화의 질문과 아동 답변을 순서대로 보여준다.
///
/// 활동 상세 조회와 따로 불러오고 따로 실패한다. 대화를 불러오지 못해도
/// 그림과 활동 기본 정보는 그대로 남고, 이 영역만 재시도할 수 있다.
class _ConversationSection extends StatefulWidget {
  const _ConversationSection({
    required this.conversationId,
    required this.repository,
    required this.voiceAnswerPlaybackRepository,
    required this.voiceAnswerAudioPlayerFactory,
  });

  final int? conversationId;
  final ActivityRepository repository;
  final VoiceAnswerPlaybackRepository? voiceAnswerPlaybackRepository;
  final VoiceAnswerAudioPlayerFactory? voiceAnswerAudioPlayerFactory;

  @override
  State<_ConversationSection> createState() => _ConversationSectionState();
}

enum _ConversationStatus { loading, success, empty, error, none }

class _ConversationSectionState extends State<_ConversationSection>
    with WidgetsBindingObserver {
  _ConversationStatus _status = _ConversationStatus.loading;
  List<ActivityConversationTurn> _turns = const [];
  Object? _failure;
  VoiceAnswerPlaybackController? _playbackController;

  /// 조회를 시작한 순서표. 활동을 바꿔 다시 부르면 값이 올라가므로, 늦게
  /// 도착한 지난 응답이 새 화면을 덮어쓰지 못한다.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createPlaybackController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(_ConversationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceAnswerPlaybackRepository !=
            widget.voiceAnswerPlaybackRepository ||
        oldWidget.voiceAnswerAudioPlayerFactory !=
            widget.voiceAnswerAudioPlayerFactory) {
      _playbackController?.dispose();
      _createPlaybackController();
    }
    if (oldWidget.conversationId != widget.conversationId ||
        oldWidget.repository != widget.repository) {
      unawaited(_playbackController?.reset());
      unawaited(_load());
    }
  }

  void _createPlaybackController() {
    final repository = widget.voiceAnswerPlaybackRepository;
    final playerFactory = widget.voiceAnswerAudioPlayerFactory;
    _playbackController = repository == null || playerFactory == null
        ? null
        : VoiceAnswerPlaybackController(repository, playerFactory());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_playbackController?.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadToken += 1;
    _playbackController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final conversationId = widget.conversationId;
    final token = ++_loadToken;
    if (conversationId == null) {
      // 대화가 없는 활동이다 — 메시지 API를 부르지 않는다.
      if (mounted) {
        setState(() {
          _status = _ConversationStatus.none;
          _turns = const [];
          _failure = null;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _status = _ConversationStatus.loading;
      _failure = null;
    });
    try {
      final messages = await widget.repository.getConversationMessages(
        conversationId,
      );
      if (!mounted || token != _loadToken) return;
      final turns = ActivityConversationTurn.group(messages);
      setState(() {
        _turns = turns;
        _status = turns.isEmpty
            ? _ConversationStatus.empty
            : _ConversationStatus.success;
      });
    } on Object catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _failure = error;
        _status = _ConversationStatus.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _DetailSection(
    title: '그림에 대한 대화',
    key: const ValueKey('activity-detail-conversation'),
    children: [_body()],
  );

  Widget _body() => switch (_status) {
    _ConversationStatus.none => const Text(
      key: ValueKey('activity-detail-conversation-none'),
      '이 활동에서 제공된 대화 정보가 없어요.',
      style: TextStyle(color: AppColors.inkMuted),
    ),
    _ConversationStatus.loading => const Padding(
      key: ValueKey('activity-detail-conversation-loading'),
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: AppLoadingView(message: '대화를 불러오고 있어요'),
    ),
    _ConversationStatus.empty => const Padding(
      key: ValueKey('activity-detail-conversation-empty'),
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: AppEmptyView(
        title: '아직 주고받은 대화가 없어요',
        message: '아이가 질문에 답하면 이곳에서 확인할 수 있어요.',
      ),
    ),
    _ConversationStatus.error => Padding(
      key: const ValueKey('activity-detail-conversation-error'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: AppFailureView(
        title: '대화를 불러오지 못했어요',
        failure: _failure,
        onRetry: _load,
      ),
    ),
    _ConversationStatus.success => Column(
      key: const ValueKey('activity-detail-conversation-turns'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, turn) in _turns.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.md),
          _ConversationTurnView(
            turn: turn,
            index: index,
            playbackController: _playbackController,
          ),
        ],
      ],
    ),
  };
}

class _ConversationTurnView extends StatelessWidget {
  const _ConversationTurnView({
    required this.turn,
    required this.index,
    required this.playbackController,
  });

  final ActivityConversationTurn turn;
  final int index;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    final question = turn.question;
    final firstAnswerId = turn.answers.isEmpty
        ? null
        : turn.answers.first.messageId;
    final turnKey = switch ((question?.messageId, firstAnswerId)) {
      (final questionId?, _) => 'conversation-turn-$questionId',
      (_, final answerId?) => 'conversation-turn-orphan-$answerId',
      _ => 'conversation-turn-empty-$index',
    };
    return Container(
      key: ValueKey(turnKey),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (question != null) _QuestionView(question: question),
          if (question != null && turn.answers.isNotEmpty)
            const SizedBox(height: AppSpacing.sm),
          for (final (index, answer) in turn.answers.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.xs),
            _AnswerView(answer: answer, playbackController: playbackController),
          ],
          if (question != null && turn.hasNoAnswer) ...[
            const SizedBox(height: AppSpacing.sm),
            _AnswerBubble(
              label: '아이 답변',
              body: question.isSkipped ? '이 질문은 건너뛰었어요.' : '아직 답변이 없어요.',
              muted: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({required this.question});
  final ActivityConversationMessageDto question;

  @override
  Widget build(BuildContext context) {
    final text = question.rawText;
    final target = question.targetObject?.objectName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MessageHeader(
          createdAt: question.createdAt,
          badges: [
            const _Pill(
              label: '도담이 질문',
              fg: AppColors.leaf,
              bg: AppColors.leafSoft,
            ),
            if (question.isSkipped)
              const _Pill(
                label: '건너뛴 질문',
                fg: AppColors.warning,
                bg: AppColors.warningSoft,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          label: 'AI 질문. ${text ?? '질문 내용을 표시할 수 없어요.'}',
          child: ExcludeSemantics(
            child: Text(
              text ?? '질문 내용을 표시할 수 없어요.',
              style: TextStyle(
                color: text == null ? AppColors.inkMuted : AppColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ),
        if (target != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '그림 속 “$target”에 대해 물었어요',
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
          ),
        ],
        if (question.options.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label:
                '질문 선택지. '
                '${question.options.map((option) => option.label).join(', ')}',
            child: ExcludeSemantics(
              child: Wrap(
                spacing: AppSpacing.xxs,
                runSpacing: AppSpacing.xxs,
                children: [
                  for (final option in question.options)
                    _Pill(
                      label: option.emoji == null
                          ? option.label
                          : '${option.emoji} ${option.label}',
                      fg: AppColors.inkMuted,
                      bg: AppColors.surface,
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AnswerView extends StatelessWidget {
  const _AnswerView({required this.answer, required this.playbackController});
  final ActivityConversationMessageDto answer;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    final (body, muted) = _answerBody(answer);
    return _AnswerBubble(
      label: '아이 답변',
      body: body,
      muted: muted,
      createdAt: answer.createdAt,
      footer: answer.messageType == 'ANSWER_VOICE' && playbackController != null
          ? VoiceAnswerPlaybackControl(
              controller: playbackController!,
              messageId: answer.messageId,
            )
          : null,
    );
  }
}

/// 배지 묶음과 오른쪽 시각으로 이루어진 메시지 머리글.
///
/// 배지를 [Wrap]에 담아 [Expanded]로 감싼다. 글자 확대(textScale)에서 배지가
/// 커지면 줄을 접어 내려가고 시각은 오른쪽에 남는다 — 한 줄 [Row]로 두면
/// 확대 시 오른쪽으로 넘친다.
class _MessageHeader extends StatelessWidget {
  const _MessageHeader({required this.badges, this.createdAt});
  final List<Widget> badges;
  final String? createdAt;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Wrap(
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: badges,
        ),
      ),
      if (createdAt case final createdAt?) ...[
        const SizedBox(width: AppSpacing.xxs),
        Text(
          _time(createdAt),
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 11.5),
        ),
      ],
    ],
  );
}

class _AnswerBubble extends StatelessWidget {
  const _AnswerBubble({
    required this.label,
    required this.body,
    required this.muted,
    this.createdAt,
    this.footer,
  });
  final String label, body;
  final bool muted;
  final String? createdAt;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: AppColors.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '$label. $body',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MessageHeader(
                  createdAt: createdAt,
                  badges: [
                    _Pill(
                      label: label,
                      fg: AppColors.lavender,
                      bg: AppColors.lavenderSoft,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  body,
                  style: TextStyle(
                    color: muted ? AppColors.inkMuted : AppColors.ink,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (footer case final footer?) ...[
          const SizedBox(height: AppSpacing.xxs),
          footer,
        ],
      ],
    ),
  );
}

/// 답변 메시지 하나를 보호자가 읽을 문장과 "내용 없음" 여부로 바꾼다.
///
/// 알 수 없는 메시지 유형이 와도 담긴 Text를 최선으로 보여주고, 그것마저
/// 없으면 안내 문구로 대체한다. 대화 전체가 실패하지 않는 것이 우선이다.
(String, bool) _answerBody(ActivityConversationMessageDto answer) {
  if (answer.isSkipped) return ('이 질문은 건너뛰었어요.', true);
  return switch (answer.messageType) {
    'ANSWER_OPTION' => _optionAnswerBody(answer),
    'ANSWER_VOICE' => _voiceAnswerBody(answer),
    _ => switch (answer.sttText ?? answer.rawText) {
      final text? when text.isNotEmpty => (text, false),
      _ => ('답변 내용이 저장되지 않았어요.', true),
    },
  };
}

(String, bool) _optionAnswerBody(ActivityConversationMessageDto answer) {
  final selected = answer.selectedResponse;
  final labels = [
    for (final option in selected?.selectedOptions ?? const [])
      option.labelSnapshot,
  ]..removeWhere((label) => label.isEmpty);
  final directText = selected?.directText ?? answer.rawText;
  final parts = [
    if (labels.isNotEmpty) labels.join(', '),
    if (directText != null && directText.isNotEmpty) '“$directText”',
  ];
  return parts.isEmpty
      ? ('답변 내용이 저장되지 않았어요.', true)
      : (parts.join('\n'), false);
}

(String, bool) _voiceAnswerBody(ActivityConversationMessageDto answer) {
  final text = answer.sttText;
  if (text != null && text.isNotEmpty) return (text, false);
  return switch (answer.speechStatus) {
    'PENDING' || 'PROCESSING' => ('목소리를 글로 바꾸고 있어요.', true),
    'FAILED' => ('목소리를 글로 바꾸지 못했어요. 녹음한 답변은 안전하게 보관했어요.', true),
    _ => ('답변 내용이 저장되지 않았어요.', true),
  };
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.outline),
    ),
    child: child,
  );
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.children,
    super.key,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => _DetailCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.leaf,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...children,
      ],
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: const TextStyle(color: AppColors.inkMuted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DetailImagePlaceholder extends StatelessWidget {
  const _DetailImagePlaceholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    key: ValueKey('activity-detail-image-placeholder'),
    color: AppColors.surfaceSoft,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: AppColors.inkMuted, size: 44),
          SizedBox(height: AppSpacing.sm),
          Text('그림을 불러오지 못했어요', style: TextStyle(color: AppColors.inkMuted)),
        ],
      ),
    ),
  );
}

String _dateTime(String isoDate) {
  final parsed = DateTime.tryParse(isoDate)?.toLocal();
  if (parsed == null) return isoDate;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${parsed.year}.${two(parsed.month)}.${two(parsed.day)} '
      '${two(parsed.hour)}:${two(parsed.minute)}';
}

/// 메시지 순서를 읽기 쉽게 보여주는 시:분. 서버 `createdAt`은 대화 내역에서
/// Offset 없는 LocalDateTime으로 오므로 그대로 읽고 변환하지 않는다.
String _time(String isoDateTime) {
  final parsed = DateTime.tryParse(isoDateTime);
  if (parsed == null) return isoDateTime;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(parsed.hour)}:${two(parsed.minute)}';
}

String _emotionLabel(String emotion) => switch (emotion) {
  'HAPPY' || 'JOY' => '기쁨',
  'SAD' => '슬픔',
  'ANGRY' => '화남',
  'SCARED' => '무서움',
  'CALM' => '편안함',
  'UNKNOWN' || 'UNSURE' => '잘 모르겠음',
  _ => emotion,
};
