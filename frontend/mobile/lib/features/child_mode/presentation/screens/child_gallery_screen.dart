import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../activity/data/dto/activity_dtos.dart';
import '../../../activity/domain/repositories/activity_repository.dart';
import '../../../child/data/dto/child_dtos.dart';

/// 아동용 "그림 전시관" — 아이가 그린 지난 그림을 미술관 전시처럼 보여준다.
///
/// 데이터는 활동 기록(HISTORY-01 `getActivities`)을 재사용한다. 썸네일이 있는
/// (=완성된 그림이 있는) 활동만 액자에 건다. 액자를 누르면 전시 홀(상세)로
/// 들어가 한 점씩 크게 감상한다.
class ChildGalleryScreen extends StatefulWidget {
  const ChildGalleryScreen({
    required this.child,
    required this.repository,
    super.key,
  });

  final ChildSummaryDto child;
  final ActivityRepository repository;

  @override
  State<ChildGalleryScreen> createState() => _ChildGalleryScreenState();
}

enum _LoadStatus { loading, error, ready }

/// 아동 화면에 필요한 그림 정보만 남긴 읽기 모델.
///
/// 보호자 활동 기록 응답의 분석·감정·리포트 필드는 이 경계를 넘기지 않는다.
final class _ChildArtwork {
  const _ChildArtwork({
    required this.drawingSessionId,
    required this.thumbnailUrl,
    required this.title,
    required this.completedAt,
  });

  final int drawingSessionId;
  final String thumbnailUrl;
  final String title;
  final String? completedAt;
}

class _ChildGalleryScreenState extends State<ChildGalleryScreen> {
  static const int _pageSize = 20;
  static const double _loadMoreThreshold = 360;

  final ScrollController _scrollController = ScrollController();
  _LoadStatus _status = _LoadStatus.loading;
  List<_ChildArtwork> _artworks = const [];
  final Set<int> _seenSessionIds = <int>{};
  int _page = 0;
  bool _hasNext = false;
  bool _loadingMore = false;
  Object? _loadMoreFailure;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ChildGalleryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child.childId != widget.child.childId ||
        !identical(oldWidget.repository, widget.repository)) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final childId = widget.child.childId;
    setState(() {
      _status = _LoadStatus.loading;
      _artworks = const [];
      _seenSessionIds.clear();
      _page = 0;
      _hasNext = false;
      _loadingMore = false;
      _loadMoreFailure = null;
    });
    try {
      var currentPage = 0;
      var page = await widget.repository.getActivities(
        childId,
        filter: _filterForPage(currentPage),
      );
      if (!mounted || generation != _generation) return;
      var artworks = _collectArtworks(page.content);
      // 완료 필터 안에도 이미지가 아직 만들어지지 않은 기록이 있을 수 있다.
      // 빈 전시관으로 단정하기 전에 다음 페이지에서 첫 작품을 찾는다.
      while (artworks.isEmpty &&
          page.hasNext &&
          page.content.isNotEmpty &&
          currentPage + 1 < page.totalPages) {
        currentPage += 1;
        page = await widget.repository.getActivities(
          childId,
          filter: _filterForPage(currentPage),
        );
        if (!mounted || generation != _generation) return;
        artworks = [...artworks, ..._collectArtworks(page.content)];
      }
      setState(() {
        _artworks = artworks;
        _page = page.page;
        _hasNext =
            page.hasNext &&
            page.content.isNotEmpty &&
            page.page + 1 < page.totalPages;
        _status = _LoadStatus.ready;
      });
      _scheduleAutoFill();
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() => _status = _LoadStatus.error);
    }
  }

  ActivityFilterDto _filterForPage(int page) =>
      ActivityFilterDto(status: 'COMPLETED', page: page, size: _pageSize);

  List<_ChildArtwork> _collectArtworks(
    Iterable<ActivitySummaryDto> activities,
  ) {
    final result = <_ChildArtwork>[];
    for (final activity in activities) {
      if (activity.sessionStatus != 'COMPLETED') continue;
      if (activity.activityKind.toUpperCase() == 'HTP') {
        for (final subject in _htpSubjectOrder) {
          HtpActivityDrawingDto? matched;
          for (final drawing in activity.htpDrawings) {
            if (drawing.drawingSubject.toUpperCase() == subject) {
              matched = drawing;
              break;
            }
          }
          if (matched == null) continue;
          final url = matched.thumbnailUrl?.trim() ?? '';
          if (url.isEmpty || !_seenSessionIds.add(matched.drawingSessionId)) {
            continue;
          }
          result.add(
            _ChildArtwork(
              drawingSessionId: matched.drawingSessionId,
              thumbnailUrl: url,
              title: '${_htpSubjectLabel(subject)} 그림',
              completedAt: activity.completedAt,
            ),
          );
        }
        continue;
      }

      final url = activity.thumbnailUrl?.trim() ?? '';
      if (url.isEmpty || !_seenSessionIds.add(activity.activityId)) continue;
      result.add(
        _ChildArtwork(
          drawingSessionId: activity.activityId,
          thumbnailUrl: url,
          title: _activityTitle(activity),
          completedAt: activity.completedAt,
        ),
      );
    }
    return result;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext || _status != _LoadStatus.ready) return;
    final generation = _generation;
    final childId = widget.child.childId;
    final nextPage = _page + 1;
    setState(() {
      _loadingMore = true;
      _loadMoreFailure = null;
    });
    try {
      final page = await widget.repository.getActivities(
        childId,
        filter: _filterForPage(nextPage),
      );
      if (!mounted || generation != _generation) return;
      final fresh = _collectArtworks(page.content);
      setState(() {
        _artworks = [..._artworks, ...fresh];
        _page = page.page;
        _hasNext =
            page.hasNext &&
            page.content.isNotEmpty &&
            page.page + 1 < page.totalPages;
        _loadingMore = false;
      });
      _scheduleAutoFill();
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailure = error;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        !_hasNext ||
        _loadingMore ||
        _loadMoreFailure != null) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      unawaited(_loadMore());
    }
  }

  void _scheduleAutoFill() {
    if (!_hasNext) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_hasNext ||
          _loadingMore ||
          _loadMoreFailure != null ||
          !_scrollController.hasClients) {
        return;
      }
      if (_scrollController.position.maxScrollExtent <= 0) {
        unawaited(_loadMore());
      }
    });
  }

  void _openDetail(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ChildGalleryDetailScreen(
          child: widget.child,
          repository: widget.repository,
          artworks: _artworks,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(gradient: _wallGradient),
      child: SafeArea(
        child: Column(
          children: [
            _GalleryTopBar(title: '${widget.child.nickname}의 그림 전시관'),
            Expanded(child: _body()),
          ],
        ),
      ),
    ),
  );

  Widget _body() {
    switch (_status) {
      case _LoadStatus.loading:
        return const _GalleryLoadingView();
      case _LoadStatus.error:
        return _GalleryStateScroll(
          child: AppErrorView(
            title: '전시관을 열지 못했어요',
            message: '잠시 후 다시 들어와 볼까?',
            onRetry: () => unawaited(_load()),
            childFriendly: true,
          ),
        );
      case _LoadStatus.ready:
        if (_artworks.isEmpty) {
          return _GalleryStateScroll(
            child: _GalleryEmptyView(
              onDraw: () => Navigator.of(context).maybePop(),
            ),
          );
        }
        return _GalleryWall(
          artworks: _artworks,
          repository: widget.repository,
          scrollController: _scrollController,
          loadingMore: _loadingMore,
          loadMoreFailure: _loadMoreFailure,
          onRetryLoadMore: () => unawaited(_loadMore()),
          onTapArtwork: _openDetail,
        );
    }
  }
}

class _GalleryStateScroll extends StatelessWidget {
  const _GalleryStateScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const ValueKey('child-gallery-state-scroll'),
    slivers: [
      SliverFillRemaining(hasScrollBody: false, child: Center(child: child)),
    ],
  );
}

class _GalleryLoadingView extends StatelessWidget {
  const _GalleryLoadingView();

  @override
  Widget build(BuildContext context) => Semantics(
    label: '지난 그림 불러오는 중',
    child: ExcludeSemantics(
      child: CustomScrollView(
        key: const ValueKey('child-gallery-loading'),
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: AppSkeleton(
                width: double.infinity,
                height: 78,
                borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.crossAxisExtent >= 760 ? 3 : 1;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: AppSpacing.xl,
                    crossAxisSpacing: AppSpacing.xl,
                    mainAxisExtent: 260,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, _) => const AppSkeleton(
                      width: double.infinity,
                      height: 260,
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppRadius.lg),
                      ),
                    ),
                    childCount: 6,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// 전시 벽 — 도슨트 인사 + 액자 그리드.
class _GalleryWall extends StatelessWidget {
  const _GalleryWall({
    required this.artworks,
    required this.repository,
    required this.scrollController,
    required this.loadingMore,
    required this.loadMoreFailure,
    required this.onRetryLoadMore,
    required this.onTapArtwork,
  });

  final List<_ChildArtwork> artworks;
  final ActivityRepository repository;
  final ScrollController scrollController;
  final bool loadingMore;
  final Object? loadMoreFailure;
  final VoidCallback onRetryLoadMore;
  final ValueChanged<int> onTapArtwork;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final columns = textScale >= 1.8
          ? (constraints.maxWidth >= 900 ? 2 : 1)
          : constraints.maxWidth >= 1200
          ? 4
          : constraints.maxWidth >= 760
          ? 3
          : constraints.maxWidth >= 480
          ? 2
          : 1;
      return CustomScrollView(
        key: const ValueKey('child-gallery-scroll'),
        controller: scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: _Docent(
              message: '우리 그림 구경하러 갈까?',
              detail: '내가 그린 그림 ${artworks.length}점',
            ),
          ),
          const SliverToBoxAdapter(child: _PictureRail()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: AppSpacing.xl,
                crossAxisSpacing: AppSpacing.xl,
                mainAxisExtent: textScale >= 1.8 ? 330 : 280,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final art = artworks[index];
                return _FramedArtwork(
                  key: ValueKey('child-artwork-${art.drawingSessionId}'),
                  artwork: art,
                  repository: repository,
                  onTap: () => onTapArtwork(index),
                );
              }, childCount: artworks.length),
            ),
          ),
          SliverToBoxAdapter(
            child: _PaginationFooter(
              loading: loadingMore,
              failed: loadMoreFailure != null,
              onRetry: onRetryLoadMore,
            ),
          ),
        ],
      );
    },
  );
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.loading,
    required this.failed,
    required this.onRetry,
  });

  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        key: const ValueKey('child-gallery-load-more'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: Semantics(
            label: '그림 더 불러오는 중',
            child: const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        ),
      );
    }
    if (failed) {
      return Padding(
        key: const ValueKey('child-gallery-load-more-error'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: AppButton(
            label: '그림 더 불러오기',
            variant: AppButtonVariant.secondary,
            expand: false,
            leading: const Icon(Icons.refresh_rounded),
            onPressed: onRetry,
          ),
        ),
      );
    }
    return const SizedBox(height: AppSpacing.lg);
  }
}

/// 벽에 걸린 액자 한 점 — 금색 액자 + 아래 명패(제목·날짜).
class _FramedArtwork extends StatelessWidget {
  const _FramedArtwork({
    required this.artwork,
    required this.repository,
    required this.onTap,
    super.key,
  });

  final _ChildArtwork artwork;
  final ActivityRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${artwork.title} 그림 크게 보기',
    child: ExcludeSemantics(
      child: _TapScale(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Hero(
                tag: 'gallery-artwork-${artwork.drawingSessionId}',
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _frameGold, width: 5),
                    boxShadow: const [
                      BoxShadow(
                        color: _frameShadow,
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AuthenticatedImage(
                      url: artwork.thumbnailUrl,
                      fetcher: repository.downloadImage,
                      fit: BoxFit.contain,
                      semanticLabel: artwork.title,
                      placeholderBuilder: (_) => Semantics(
                        label: '그림을 불러오지 못했어요',
                        child: ExcludeSemantics(
                          child: ColoredBox(
                            key: const ValueKey('child-artwork-image-fallback'),
                            color: AppColors.surfaceSoft,
                            child: Center(
                              child: Icon(
                                Icons.image_outlined,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _Plaque(
              title: artwork.title,
              date: _formatDate(artwork.completedAt),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 미술관 명패.
class _Plaque extends StatelessWidget {
  const _Plaque({required this.title, required this.date, this.large = false});

  final String title;
  final String date;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: large ? 20 : 12,
      vertical: large ? 10 : 7,
    ),
    decoration: BoxDecoration(
      color: _plaque,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _plaqueBorder),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.ink,
            fontSize: large ? 18 : 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (date.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              date,
              style: TextStyle(
                color: _plaqueMuted,
                fontSize: large ? 13 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    ),
  );
}

/// 도슨트 도담이 — 캐릭터 + 말풍선.
class _Docent extends StatelessWidget {
  const _Docent({required this.message, required this.detail});

  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.md,
      AppSpacing.xl,
      AppSpacing.xs,
    ),
    child: Row(
      children: [
        Image.asset(
          'assets/characters/costumes/dodam_base.png',
          width: 64,
          height: 64,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _plaqueBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// 전시실 벽 몰딩(picture rail) — 벽 느낌을 주는 얇은 장식 띠.
class _PictureRail extends StatelessWidget {
  const _PictureRail();

  @override
  Widget build(BuildContext context) => Container(
    height: 8,
    margin: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.md,
      AppSpacing.xl,
      0,
    ),
    decoration: BoxDecoration(
      color: _rail,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

/// 빈 상태 — 빈 액자 + 첫 작품 유도.
class _GalleryEmptyView extends StatelessWidget {
  const _GalleryEmptyView({required this.onDraw});

  final VoidCallback onDraw;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _emptyFrame(70, 88, _emptyFrameSoft),
              const SizedBox(width: AppSpacing.md),
              _emptyFrame(88, 108, _frameGold, icon: Icons.add_rounded),
              const SizedBox(width: AppSpacing.md),
              _emptyFrame(70, 88, _emptyFrameSoft),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const Text(
            '아직 전시된 그림이 없어요',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            '그림을 그리면 이곳에 하나씩 전시돼요.\n첫 작품을 걸어볼까?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.inkMuted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _TapScale(
            onTap: onDraw,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.brandYellow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.brandYellowPressed),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.brush_rounded, color: AppColors.ink, size: 20),
                  SizedBox(width: AppSpacing.xs),
                  Text(
                    '그림 그리러 가기',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  static Widget _emptyFrame(
    double w,
    double h,
    Color border, {
    IconData? icon,
  }) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: _emptyFrameFill,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: border, width: 4),
    ),
    child: icon == null ? null : Icon(icon, color: _frameGold, size: 30),
  );
}

/// 전시 홀(상세) — 한 점씩 크게 조명받으며 좌우로 감상한다.
class _ChildGalleryDetailScreen extends StatefulWidget {
  const _ChildGalleryDetailScreen({
    required this.child,
    required this.repository,
    required this.artworks,
    required this.initialIndex,
  });

  final ChildSummaryDto child;
  final ActivityRepository repository;
  final List<_ChildArtwork> artworks;
  final int initialIndex;

  @override
  State<_ChildGalleryDetailScreen> createState() =>
      _ChildGalleryDetailScreenState();
}

class _ChildGalleryDetailScreenState extends State<_ChildGalleryDetailScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.artworks.length) return;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: _wallGradient),
        child: SafeArea(
          child: Column(
            children: [
              _GalleryTopBar(title: '${widget.child.nickname}의 그림 전시관'),
              _DocentLine(
                message: "'${widget.artworks[_index].title}', 참 멋지게 그렸다!",
              ),
              Expanded(
                child: Row(
                  children: [
                    _HallChevron(
                      icon: Icons.chevron_left_rounded,
                      semanticLabel: '이전 그림',
                      enabled: _index > 0,
                      onTap: () => _step(-1),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _controller,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemCount: widget.artworks.length,
                        itemBuilder: (context, i) => _Spotlight(
                          artwork: widget.artworks[i],
                          repository: widget.repository,
                        ),
                      ),
                    ),
                    _HallChevron(
                      icon: Icons.chevron_right_rounded,
                      semanticLabel: '다음 그림',
                      enabled: _index < widget.artworks.length - 1,
                      onTap: () => _step(1),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Text(
                  '${_index + 1} / ${widget.artworks.length}',
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 한 작품을 조명받는 전시대에 올린 모습 — 큰 액자 + 명패.
class _Spotlight extends StatelessWidget {
  const _Spotlight({required this.artwork, required this.repository});

  final _ChildArtwork artwork;
  final ActivityRepository repository;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final frameSize = (constraints.maxWidth - AppSpacing.lg * 2).clamp(
        120.0,
        360.0,
      );
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: frameSize,
                height: frameSize,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: _spotlightBacking,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Hero(
                  tag: 'gallery-artwork-${artwork.drawingSessionId}',
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _frameGold, width: 8),
                      boxShadow: const [
                        BoxShadow(
                          color: _frameShadow,
                          blurRadius: 26,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AuthenticatedImage(
                        url: artwork.thumbnailUrl,
                        fetcher: repository.downloadImage,
                        fit: BoxFit.contain,
                        semanticLabel: artwork.title,
                        placeholderBuilder: (_) => Semantics(
                          label: '큰 그림을 불러오지 못했어요',
                          child: ExcludeSemantics(
                            child: ColoredBox(
                              key: const ValueKey(
                                'child-artwork-detail-fallback',
                              ),
                              color: AppColors.surfaceSoft,
                              child: Center(
                                child: Icon(
                                  Icons.image_outlined,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _Plaque(
                title: artwork.title,
                date: _formatDate(artwork.completedAt),
                large: true,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _HallChevron extends StatelessWidget {
  const _HallChevron({
    required this.icon,
    required this.semanticLabel,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: semanticLabel,
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.35,
          duration: const Duration(milliseconds: 150),
          child: _TapScale(
            onTap: enabled ? onTap : null,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: _plaqueBorder),
                boxShadow: const [
                  BoxShadow(
                    color: _frameShadow,
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: AppColors.inkMuted, size: 30),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DocentLine extends StatelessWidget {
  const _DocentLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/characters/costumes/dodam_base.png',
          width: 34,
          height: 34,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            '도담이: $message',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 상단바 — 뒤로 + 가운데 제목.
class _GalleryTopBar extends StatelessWidget {
  const _GalleryTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: '뒤로 가기',
          child: ExcludeSemantics(
            child: _TapScale(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.inkMuted,
                      size: 20,
                    ),
                    SizedBox(width: AppSpacing.xs),
                    Text(
                      '뒤로',
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    ),
  );
}

/// 눌림 즉시 살짝 줄어드는 피드백(홈 화면과 동일한 결). 비활성이면 반응하지 않는다.
class _TapScale extends StatefulWidget {
  const _TapScale({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  bool _down = false;

  void _set(bool value) {
    if (widget.onTap == null || _down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _set(true),
    onTapUp: (_) => _set(false),
    onTapCancel: () => _set(false),
    onTap: widget.onTap,
    child: AnimatedScale(
      scale: _down ? 0.96 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}

String _activityTitle(ActivitySummaryDto artwork) {
  final title = artwork.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  return artwork.drawingType.name;
}

const List<String> _htpSubjectOrder = ['HOUSE', 'TREE', 'PERSON'];

String _htpSubjectLabel(String subject) => switch (subject) {
  'HOUSE' => '집',
  'TREE' => '나무',
  'PERSON' => '사람',
  _ => subject,
};

String _formatDate(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  return '${dt.month}월 ${dt.day}일';
}

const LinearGradient _wallGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFFFDF6), Color(0xFFFBF1D9)],
);
const Color _frameGold = Color(0xFFD8B15A);
const Color _frameShadow = Color(0x24A9805A);
const Color _plaque = Color(0xFFF6ECD8);
const Color _plaqueBorder = Color(0xFFE7D9BE);
const Color _plaqueMuted = Color(0xFF9A8B78);
const Color _rail = Color(0xFFEADFC6);
const Color _spotlightBacking = Color(0xFFFFFBEF);
const Color _emptyFrameFill = Color(0xFFFDF8EC);
const Color _emptyFrameSoft = Color(0xFFD8C39A);
