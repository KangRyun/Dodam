import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../activity/data/dto/activity_dtos.dart';
import '../../../activity/domain/repositories/activity_repository.dart';

enum _HtpReportGalleryStatus { loading, ready, fallback }

const _htpReportSubjects = <({String code, String label})>[
  (code: 'HOUSE', label: '집'),
  (code: 'TREE', label: '나무'),
  (code: 'PERSON', label: '사람'),
];

/// HTP 리포트가 속한 활동의 집·나무·사람 그림을 활동기록에서 찾는다.
///
/// Report 상세 계약에는 `htpAssessmentId`가 없으므로 날짜나 목록 순서를
/// 추정하지 않는다. 대신 Report의 `drawingSessionId`가 `htpDrawings`에 실제로
/// 포함된 HTP 활동만 선택하고, 그 동일 항목의 세 그림을 서버 정본으로 쓴다.
class HtpReportGallery extends StatefulWidget {
  const HtpReportGallery({
    required this.childId,
    required this.reportDrawingSessionId,
    required this.repository,
    required this.fallback,
    super.key,
  });

  final int childId;
  final int reportDrawingSessionId;
  final ActivityRepository? repository;
  final Widget fallback;

  @override
  State<HtpReportGallery> createState() => _HtpReportGalleryState();
}

class _HtpReportGalleryState extends State<HtpReportGallery> {
  _HtpReportGalleryStatus _status = _HtpReportGalleryStatus.loading;
  Map<String, HtpActivityDrawingDto> _drawingsBySubject = const {};
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _startLoad(notify: false);
  }

  @override
  void didUpdateWidget(covariant HtpReportGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId ||
        oldWidget.reportDrawingSessionId != widget.reportDrawingSessionId ||
        !identical(oldWidget.repository, widget.repository)) {
      _startLoad();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  void _startLoad({bool notify = true}) {
    final generation = ++_loadGeneration;
    if (notify) {
      setState(() {
        _status = _HtpReportGalleryStatus.loading;
        _drawingsBySubject = const {};
      });
    } else {
      _status = _HtpReportGalleryStatus.loading;
      _drawingsBySubject = const {};
    }
    unawaited(_load(generation));
  }

  Future<void> _load(int generation) async {
    final repository = widget.repository;
    final childId = widget.childId;
    final reportDrawingSessionId = widget.reportDrawingSessionId;
    if (repository == null || childId <= 0 || reportDrawingSessionId <= 0) {
      _completeLoad(generation, status: _HtpReportGalleryStatus.fallback);
      return;
    }

    try {
      var requestedPage = 0;
      while (true) {
        final page = await repository.getActivities(
          childId,
          filter: ActivityFilterDto(page: requestedPage, size: 20),
        );
        if (!_isCurrent(
          generation,
          childId,
          reportDrawingSessionId,
          repository,
        )) {
          return;
        }

        final matches = [
          for (final activity in page.content)
            if (activity.isHtp &&
                activity.htpDrawings.any(
                  (drawing) =>
                      drawing.drawingSessionId == reportDrawingSessionId,
                ))
              activity,
        ];
        if (matches.length > 1) {
          _completeLoad(generation, status: _HtpReportGalleryStatus.fallback);
          return;
        }
        if (matches case [final target]) {
          if (target.htpDrawings.isEmpty) {
            _completeLoad(generation, status: _HtpReportGalleryStatus.fallback);
            return;
          }
          final drawings = <String, HtpActivityDrawingDto>{};
          for (final drawing in target.htpDrawings) {
            final subject = drawing.drawingSubject.toUpperCase();
            if (_htpReportSubjects.any((item) => item.code == subject)) {
              drawings.putIfAbsent(subject, () => drawing);
            }
          }
          _completeLoad(
            generation,
            status: _HtpReportGalleryStatus.ready,
            drawings: drawings,
          );
          return;
        }

        final nextPage = page.page + 1;
        if (!page.hasNext ||
            nextPage >= page.totalPages ||
            nextPage <= requestedPage) {
          _completeLoad(generation, status: _HtpReportGalleryStatus.fallback);
          return;
        }
        requestedPage = nextPage;
      }
    } on Object {
      _completeLoad(generation, status: _HtpReportGalleryStatus.fallback);
    }
  }

  bool _isCurrent(
    int generation,
    int childId,
    int reportDrawingSessionId,
    ActivityRepository repository,
  ) =>
      mounted &&
      generation == _loadGeneration &&
      widget.childId == childId &&
      widget.reportDrawingSessionId == reportDrawingSessionId &&
      identical(widget.repository, repository);

  void _completeLoad(
    int generation, {
    required _HtpReportGalleryStatus status,
    Map<String, HtpActivityDrawingDto> drawings = const {},
  }) {
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _status = status;
      _drawingsBySubject = drawings;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_status == _HtpReportGalleryStatus.fallback) return widget.fallback;
    return Column(
      key: const ValueKey('htp-report-gallery'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = switch (constraints.maxWidth) {
              >= 720 => 3,
              >= 440 => 2,
              _ => 1,
            };
            const gap = AppSpacing.md;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final subject in _htpReportSubjects)
                  SizedBox(
                    width: width,
                    child: _HtpReportSubjectCard(
                      subject: subject.code,
                      label: subject.label,
                      drawing: _drawingsBySubject[subject.code],
                      loading: _status == _HtpReportGalleryStatus.loading,
                      repository: widget.repository,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HtpReportSubjectCard extends StatelessWidget {
  const _HtpReportSubjectCard({
    required this.subject,
    required this.label,
    required this.drawing,
    required this.loading,
    required this.repository,
  });

  final String subject;
  final String label;
  final HtpActivityDrawingDto? drawing;
  final bool loading;
  final ActivityRepository? repository;

  @override
  Widget build(BuildContext context) {
    final rawUrl = drawing?.thumbnailUrl;
    final url = rawUrl == null || rawUrl.trim().isEmpty ? null : rawUrl;
    return Container(
      key: ValueKey('htp-report-preview-$subject'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label: '$label 그림 단계',
            child: ExcludeSemantics(
              child: Text(
                label,
                key: ValueKey('htp-report-preview-label-$subject'),
                textAlign: TextAlign.center,
                style: AppTypography.label,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: loading
                  ? Semantics(
                      label: '$label 그림 불러오는 중',
                      child: const ExcludeSemantics(
                        child: AppSkeleton(
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                    )
                  : AuthenticatedImage(
                      key: ValueKey('htp-report-image-$subject'),
                      url: url,
                      fetcher: repository?.downloadImage ?? _missingFetcher,
                      fit: BoxFit.contain,
                      semanticLabel: '$label 그림',
                      placeholderBuilder: (_) =>
                          _HtpReportSubjectFailure(label: label),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<Never> _missingFetcher(String _) =>
    Future<Never>.error(StateError('Activity repository is unavailable.'));

class _HtpReportSubjectFailure extends StatelessWidget {
  const _HtpReportSubjectFailure({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label 그림을 불러오지 못했어요.',
    child: ExcludeSemantics(
      child: ColoredBox(
        color: AppColors.canvas,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              '$label 그림을 불러오지 못했어요.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySm.copyWith(color: AppColors.inkMuted),
            ),
          ),
        ),
      ),
    ),
  );
}
