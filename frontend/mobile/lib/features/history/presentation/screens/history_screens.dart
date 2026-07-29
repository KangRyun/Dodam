import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/state/guardian_child_controller.dart';
import '../../../../app/widgets/app_failure_view.dart';
import '../../../../design_system/design_system.dart';
import '../../../activity/data/dto/activity_dtos.dart';
import '../../../activity/domain/repositories/activity_repository.dart';
import '../../../child/data/dto/child_dtos.dart';

enum _HistoryStatus { loading, success, empty, error, noChild }

enum _PeriodFilter { all, recent30Days }

enum _StatusFilter { all, done, analyzing, failed }

enum _CardStatus { done, analyzing, failed, draft }

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
  int? _selectedActivityId;
  String? _drawingType;
  _PeriodFilter _period = _PeriodFilter.all;
  _StatusFilter _statusFilter = _StatusFilter.all;

  /// 마지막으로 불러온 아동. 컨트롤러는 여러 이유로 알림을 보내므로,
  /// 대상 아동이 실제로 바뀐 경우에만 다시 조회한다.
  int? _loadedChildId;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    widget.childController.removeListener(_onChildChanged);
    super.dispose();
  }

  void _onChildChanged() {
    if (widget.childController.selectedChildId == _loadedChildId) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    final childId = widget.childController.selectedChildId;
    _loadedChildId = childId;
    if (childId == null) {
      setState(() {
        _status = _HistoryStatus.noChild;
        _activities = const [];
        _selectedActivityId = null;
      });
      return;
    }
    setState(() {
      _status = _HistoryStatus.loading;
      _failure = null;
    });
    try {
      final now = DateTime.now().toUtc();
      final response = await widget.repository.getActivities(
        childId,
        filter: ActivityFilterDto(
          // HISTORY-01 from/to는 date(yyyy-MM-dd) — datetime을 보내면 서버가
          // 필터를 적용하지 못한다.
          from: _period == _PeriodFilter.recent30Days
              ? _isoDate(now.subtract(const Duration(days: 30)))
              : null,
          to: _period == _PeriodFilter.recent30Days ? _isoDate(now) : null,
          drawingType: _drawingType,
        ),
      );
      if (!mounted) return;
      final activities = response.content;
      final knownTypes = <String, ActivityDrawingTypeDto>{
        for (final type in _knownTypes) type.code: type,
        for (final activity in activities)
          activity.drawingType.code: activity.drawingType,
      }.values.toList(growable: false);
      final selectedStillExists = activities.any(
        (activity) => activity.activityId == _selectedActivityId,
      );
      setState(() {
        _activities = activities;
        _knownTypes = knownTypes;
        _selectedActivityId = selectedStillExists
            ? _selectedActivityId
            : activities.firstOrNull?.activityId;
        _status = activities.isEmpty
            ? _HistoryStatus.empty
            : _HistoryStatus.success;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _status = _HistoryStatus.error;
        });
      }
    }
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

  Widget _content(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (!widget.embedded) ...[
              IconButton(
                key: const ValueKey('activity-history-back'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppColors.ink,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            const Expanded(
              child: Text(
                '활동 기록',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_status != _HistoryStatus.noChild &&
            _status != _HistoryStatus.loading)
          _buildFilters(),
        if (_status != _HistoryStatus.noChild &&
            _status != _HistoryStatus.loading)
          const SizedBox(height: AppSpacing.md),
        Expanded(child: _buildBody()),
      ],
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
          onSelected: (activityId) =>
              setState(() => _selectedActivityId = activityId),
          onReport: _openReport,
        );
        final preview = _PreviewPane(
          activity: _selectedActivity,
          repository: widget.repository,
          onReport: _openReport,
        );
        if (constraints.maxWidth < 760) {
          return ListView(
            key: const ValueKey('activity-history-small-layout'),
            children: [
              list(scrollable: false),
              const SizedBox(height: AppSpacing.sm),
              const _DeleteNotice(),
              const SizedBox(height: AppSpacing.lg),
              preview,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  Expanded(child: list()),
                  const SizedBox(height: AppSpacing.sm),
                  const _DeleteNotice(),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(flex: 4, child: preview),
          ],
        );
      },
    ),
  };
}

// ── 필터 ─────────────────────────────────────────────────────────────
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
  Widget build(BuildContext context) => Wrap(
    key: const ValueKey('activity-history-filters'),
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      _FilterDropdown<int>(
        key: const ValueKey('activity-child-filter'),
        label: '아동',
        value: selectedChildId,
        items: [for (final child in children) (child.childId, child.nickname)],
        onChanged: (value) {
          if (value != null) onChildChanged(value);
        },
      ),
      _FilterDropdown<_PeriodFilter>(
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
      _FilterDropdown<String?>(
        key: const ValueKey('activity-type-filter'),
        label: '유형',
        value: drawingType,
        items: [
          const (null, '전체 활동'),
          for (final type in drawingTypes) (type.code, type.name),
        ],
        onChanged: onDrawingTypeChanged,
      ),
      _FilterDropdown<_StatusFilter>(
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
    ],
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
  Widget build(BuildContext context) => SizedBox(
    width: 168,
    child: DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      items: [
        for (final item in items)
          DropdownMenuItem<T>(value: item.$1, child: Text(item.$2)),
      ],
      onChanged: onChanged,
    ),
  );
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
  });
  final List<ActivitySummaryDto> activities;
  final int? selectedActivityId;
  final ActivityRepository repository;
  final ValueChanged<int> onSelected;
  final ValueChanged<ActivitySummaryDto> onReport;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return const AppEmptyView(
        key: ValueKey('activity-history-filtered-empty'),
        title: '조건에 맞는 활동이 없어요',
        message: '필터를 바꿔 다시 확인해 보세요.',
      );
    }
    return ListView.separated(
      key: const ValueKey('activity-history-list'),
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: activities.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
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
  }
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
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        key: ValueKey('activity-${activity.activityId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? AppColors.leaf : AppColors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Thumbnail(
                url: activity.thumbnailUrl,
                repository: repository,
                size: 56,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title ?? activity.drawingType.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_date(activity.completedAt ?? activity.startedAt)} · '
                      '${_inputLabel(activity.inputMethod)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 12,
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
              const SizedBox(width: AppSpacing.sm),
              _CardAction(
                status: status,
                reportReady: _reportReady(activity),
                onReport: onReport,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.status,
    required this.reportReady,
    required this.onReport,
  });
  final _CardStatus status;
  final bool reportReady;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final (label, onTap) = switch (status) {
      _CardStatus.done => ('관찰 리포트 보기', reportReady ? onReport : null),
      _CardStatus.analyzing => ('관찰 리포트 보기', null),
      _CardStatus.failed => (
        '재분석 요청',
        () => _snack(context, '재분석 요청은 준비 중이에요.'),
      ),
      _CardStatus.draft => (
        '이어 그리기',
        () => _snack(context, '이어 그리기는 준비 중이에요.'),
      ),
    };
    final enabled = onTap != null;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: enabled ? AppColors.leaf : AppColors.inkMuted,
        backgroundColor: AppColors.surfaceSoft,
        disabledForegroundColor: AppColors.inkMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: AppColors.outline),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ── 우측 프리뷰(그림 + 관찰 리포트 보기) ─────────────────────────────
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.activity,
    required this.repository,
    required this.onReport,
  });
  final ActivitySummaryDto? activity;
  final ActivityRepository repository;
  final ValueChanged<ActivitySummaryDto> onReport;

  @override
  Widget build(BuildContext context) {
    final activity = this.activity;
    return Container(
      key: const ValueKey('activity-history-summary'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: activity == null
          ? const AppEmptyView(title: '활동을 선택해 주세요')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  activity.title ?? activity.drawingType.name,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: _Thumbnail(
                      url: activity.thumbnailUrl,
                      repository: repository,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  key: const ValueKey('activity-report-cta'),
                  label: '관찰 리포트 보기',
                  onPressed: _reportReady(activity)
                      ? () => onReport(activity)
                      : null,
                ),
              ],
            ),
    );
  }
}

class _DeleteNotice extends StatelessWidget {
  const _DeleteNotice();
  @override
  Widget build(BuildContext context) => const Text(
    '기록 삭제 시 연결된 대화·분석·리포트가 함께 지워져요.',
    textAlign: TextAlign.center,
    style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
  );
}

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
  });
  final String? url;
  final ActivityRepository repository;
  final double? size;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    final image = AuthenticatedImage(
      url: url,
      fetcher: repository.downloadImage,
      fit: fit,
      placeholderBuilder: (_) => Container(
        key: const ValueKey('activity-thumbnail-placeholder'),
        color: AppColors.surfaceSoft,
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: AppColors.inkMuted),
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

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 관찰 리포트로 진입 가능한지(완료된 리포트가 있는지).
bool _reportReady(ActivitySummaryDto activity) {
  final report = activity.report;
  return report != null && report.reportStatus == 'COMPLETED';
}

_CardStatus _cardStatus(ActivitySummaryDto activity) {
  if (activity.sessionStatus == 'DRAFT') return _CardStatus.draft;
  final reportStatus = activity.report?.reportStatus;
  if (activity.analysisStatus == 'FAILED' || reportStatus == 'FAILED') {
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
    super.key,
  });

  final String activityId;
  final ActivityRepository repository;

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
    ),
  };
}

class _ActivityDetailContent extends StatelessWidget {
  const _ActivityDetailContent({
    required this.activity,
    required this.repository,
  });
  final ActivityDetailDto activity;
  final ActivityRepository repository;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final left = _ActivityArtwork(activity: activity, repository: repository);
      final right = _ActivityInformation(activity: activity);
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

  ActivityAssetDto? get _asset {
    for (final asset in activity.assets.reversed) {
      if (asset.assetType == 'FINAL') return asset;
    }
    return activity.assets.lastOrNull;
  }

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
            url: _asset?.fileUrl,
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
  const _ActivityInformation({required this.activity});
  final ActivityDetailDto activity;

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
          if (activity.expressedEmotionText case final text?) ...[
            const SizedBox(height: AppSpacing.md),
            Text('“$text”', style: const TextStyle(color: AppColors.ink)),
          ],
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _DetailSection(
        title: '대화 정보',
        key: const ValueKey('activity-detail-conversation'),
        children: [
          if (activity.conversation case final conversation?) ...[
            _DetailLine(label: '대화 상태', value: conversation.conversationStatus),
            _DetailLine(label: '질문 수', value: '${conversation.questionCount}개'),
            if (conversation.completedAt case final completedAt?)
              _DetailLine(label: '대화 완료', value: _dateTime(completedAt)),
          ] else
            const Text(
              '이 활동에서 제공된 대화 정보가 없어요.',
              style: TextStyle(color: AppColors.inkMuted),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _DetailSection(
        title: '분석과 관찰 요약',
        key: const ValueKey('activity-detail-analysis'),
        children: [
          if (activity.analysis case final analysis?)
            _DetailLine(label: '분석 상태', value: analysis.analysisStatus)
          else
            const Text(
              '아직 생성된 요약이 없어요.',
              style: TextStyle(color: AppColors.inkMuted),
            ),
        ],
      ),
      if (activity.report case final report?) ...[
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('activity-report-cta'),
          label: '관찰 리포트 보기',
          onPressed: () => AppNavigation.pushNamed(
            context,
            AppRoutes.report(report.reportId.toString()),
          ),
        ),
      ],
    ],
  );
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

String _emotionLabel(String emotion) => switch (emotion) {
  'HAPPY' || 'JOY' => '기쁨',
  'SAD' => '슬픔',
  'ANGRY' => '화남',
  'SCARED' => '무서움',
  'CALM' => '편안함',
  'UNKNOWN' || 'UNSURE' => '잘 모르겠음',
  _ => emotion,
};
