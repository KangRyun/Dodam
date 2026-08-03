import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../data/dto/activity_dtos.dart';
import '../../domain/repositories/activity_repository.dart';

enum _HtpPreviewHistoryStatus { loading, ready, failure }

const _htpPreviewSubjects = <({String code, String label})>[
  (code: 'HOUSE', label: '집'),
  (code: 'TREE', label: '나무'),
  (code: 'PERSON', label: '사람'),
];

/// 현재 HTP assessment의 집·나무·사람 썸네일을 활동기록에서 찾아 표시한다.
///
/// 그림 bytes를 HOUSE→TREE→PERSON route에 누적하지 않고, 서버가 확정한
/// `htpDrawings`를 감정 화면 진입 시 한 번 조회한다(S15P11B209-846).
class HtpEmotionPreviewGallery extends StatefulWidget {
  const HtpEmotionPreviewGallery({
    required this.childId,
    required this.assessmentId,
    required this.repository,
    super.key,
  });

  final String childId;
  final int assessmentId;
  final ActivityRepository? repository;

  @override
  State<HtpEmotionPreviewGallery> createState() =>
      _HtpEmotionPreviewGalleryState();
}

class _HtpEmotionPreviewGalleryState extends State<HtpEmotionPreviewGallery> {
  _HtpPreviewHistoryStatus _status = _HtpPreviewHistoryStatus.loading;
  Map<String, HtpActivityDrawingDto> _drawingsBySubject = const {};
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _startLoad(notify: false);
  }

  @override
  void didUpdateWidget(covariant HtpEmotionPreviewGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId ||
        oldWidget.assessmentId != widget.assessmentId ||
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
        _status = _HtpPreviewHistoryStatus.loading;
        _drawingsBySubject = const {};
      });
    } else {
      _status = _HtpPreviewHistoryStatus.loading;
      _drawingsBySubject = const {};
    }
    unawaited(_load(generation));
  }

  Future<void> _load(int generation) async {
    final repository = widget.repository;
    final childId = int.tryParse(widget.childId);
    final assessmentId = widget.assessmentId;
    if (repository == null || childId == null) {
      _completeLoad(generation, status: _HtpPreviewHistoryStatus.failure);
      return;
    }

    try {
      var requestedPage = 0;
      while (true) {
        final page = await repository.getActivities(
          childId,
          filter: ActivityFilterDto(page: requestedPage, size: 20),
        );
        if (!_isCurrent(generation, childId, assessmentId, repository)) return;

        ActivitySummaryDto? target;
        for (final activity in page.content) {
          if (activity.isHtp && activity.htpAssessmentId == assessmentId) {
            target = activity;
            break;
          }
        }
        if (target != null) {
          final drawings = <String, HtpActivityDrawingDto>{};
          for (final drawing in target.htpDrawings) {
            final subject = drawing.drawingSubject.toUpperCase();
            if (_htpPreviewSubjects.any((item) => item.code == subject)) {
              drawings.putIfAbsent(subject, () => drawing);
            }
          }
          _completeLoad(
            generation,
            status: _HtpPreviewHistoryStatus.ready,
            drawings: drawings,
          );
          return;
        }

        final nextPage = page.page + 1;
        if (!page.hasNext ||
            nextPage >= page.totalPages ||
            nextPage <= requestedPage) {
          _completeLoad(generation, status: _HtpPreviewHistoryStatus.ready);
          return;
        }
        requestedPage = nextPage;
      }
    } on Object {
      _completeLoad(generation, status: _HtpPreviewHistoryStatus.failure);
    }
  }

  bool _isCurrent(
    int generation,
    int childId,
    int assessmentId,
    ActivityRepository repository,
  ) =>
      mounted &&
      generation == _loadGeneration &&
      int.tryParse(widget.childId) == childId &&
      widget.assessmentId == assessmentId &&
      identical(widget.repository, repository);

  void _completeLoad(
    int generation, {
    required _HtpPreviewHistoryStatus status,
    Map<String, HtpActivityDrawingDto> drawings = const {},
  }) {
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _status = status;
      _drawingsBySubject = drawings;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('htp-emotion-preview-gallery'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_status == _HtpPreviewHistoryStatus.failure) ...[
        Semantics(
          container: true,
          label: '완성한 그림을 불러오지 못했어요.',
          child: const ExcludeSemantics(
            child: Text(
              '완성한 그림을 불러오지 못했어요.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySm,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = switch (constraints.maxWidth) {
            >= 720 => 3,
            >= 440 => 2,
            _ => 1,
          };
          const gap = AppSpacing.md;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final subject in _htpPreviewSubjects)
                SizedBox(
                  width: width,
                  child: _HtpSubjectPreviewCard(
                    subject: subject.code,
                    label: subject.label,
                    drawing: _drawingsBySubject[subject.code],
                    loading: _status == _HtpPreviewHistoryStatus.loading,
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

class _HtpSubjectPreviewCard extends StatelessWidget {
  const _HtpSubjectPreviewCard({
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
      key: ValueKey('htp-emotion-preview-$subject'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEF8),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label: '$label 그림 주제',
            child: ExcludeSemantics(
              child: Text(
                label,
                key: ValueKey('htp-emotion-preview-label-$subject'),
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
                      key: ValueKey('htp-emotion-image-$subject'),
                      url: url,
                      fetcher: repository?.downloadImage ?? _missingFetcher,
                      fit: BoxFit.contain,
                      semanticLabel: '$label 그림',
                      placeholderBuilder: (_) =>
                          _HtpSubjectFailure(label: label),
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

class _HtpSubjectFailure extends StatelessWidget {
  const _HtpSubjectFailure({required this.label});

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
