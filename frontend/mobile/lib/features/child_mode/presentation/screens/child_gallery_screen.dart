import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/network/api_page.dart';
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

class _ChildGalleryScreenState extends State<ChildGalleryScreen> {
  _LoadStatus _status = _LoadStatus.loading;
  List<ActivitySummaryDto> _artworks = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _status = _LoadStatus.loading);
    try {
      final ApiPage<ActivitySummaryDto> page = await widget.repository
          .getActivities(widget.child.childId, filter: const ActivityFilterDto(size: 60));
      if (!mounted) return;
      // 전시관에는 "볼 그림"만 건다 — 썸네일(완성 이미지)이 있는 활동만.
      final artworks = page.content
          .where((a) => (a.thumbnailUrl ?? '').isNotEmpty)
          .toList(growable: false);
      setState(() {
        _artworks = artworks;
        _status = _LoadStatus.ready;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _status = _LoadStatus.error);
    }
  }

  void _openDetail(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChildGalleryDetailScreen(
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
        return const AppLoadingView(
          message: '전시할 그림을 모으고 있어요',
          childFriendly: true,
        );
      case _LoadStatus.error:
        return AppErrorView(
          title: '전시관을 열지 못했어요',
          message: '잠시 후 다시 들어와 볼까?',
          onRetry: () => unawaited(_load()),
          childFriendly: true,
        );
      case _LoadStatus.ready:
        if (_artworks.isEmpty) {
          return _GalleryEmptyView(onDraw: () => Navigator.of(context).maybePop());
        }
        return _GalleryWall(
          nickname: widget.child.nickname,
          artworks: _artworks,
          repository: widget.repository,
          onTapArtwork: _openDetail,
        );
    }
  }
}

/// 전시 벽 — 도슨트 인사 + 액자 그리드.
class _GalleryWall extends StatelessWidget {
  const _GalleryWall({
    required this.nickname,
    required this.artworks,
    required this.repository,
    required this.onTapArtwork,
  });

  final String nickname;
  final List<ActivitySummaryDto> artworks;
  final ActivityRepository repository;
  final ValueChanged<int> onTapArtwork;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 4
          : constraints.maxWidth >= 620
          ? 3
          : 2;
      return CustomScrollView(
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
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final art = artworks[index];
                return _FramedArtwork(
                  artwork: art,
                  repository: repository,
                  onTap: () => onTapArtwork(index),
                );
              }, childCount: artworks.length),
            ),
          ),
        ],
      );
    },
  );
}

/// 벽에 걸린 액자 한 점 — 금색 액자 + 아래 명패(제목·날짜).
class _FramedArtwork extends StatelessWidget {
  const _FramedArtwork({
    required this.artwork,
    required this.repository,
    required this.onTap,
  });

  final ActivitySummaryDto artwork;
  final ActivityRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${_artworkTitle(artwork)} 그림 크게 보기',
    child: ExcludeSemantics(
      child: _TapScale(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Hero(
                tag: 'gallery-artwork-${artwork.activityId}',
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
                      semanticLabel: _artworkTitle(artwork),
                      placeholderBuilder: (_) => const ColoredBox(
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
            const SizedBox(height: 10),
            _Plaque(
              title: _artworkTitle(artwork),
              date: _formatDate(artwork.completedAt ?? artwork.startedAt),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 13,
              ),
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
    child: icon == null
        ? null
        : Icon(icon, color: _frameGold, size: 30),
  );
}

/// 전시 홀(상세) — 한 점씩 크게 조명받으며 좌우로 감상한다.
class ChildGalleryDetailScreen extends StatefulWidget {
  const ChildGalleryDetailScreen({
    required this.child,
    required this.repository,
    required this.artworks,
    required this.initialIndex,
    super.key,
  });

  final ChildSummaryDto child;
  final ActivityRepository repository;
  final List<ActivitySummaryDto> artworks;
  final int initialIndex;

  @override
  State<ChildGalleryDetailScreen> createState() =>
      _ChildGalleryDetailScreenState();
}

class _ChildGalleryDetailScreenState extends State<ChildGalleryDetailScreen> {
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
                message:
                    "'${_artworkTitle(widget.artworks[_index])}', 참 멋지게 그렸다!",
              ),
              Expanded(
                child: Row(
                  children: [
                    _HallChevron(
                      icon: Icons.chevron_left_rounded,
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

  final ActivitySummaryDto artwork;
  final ActivityRepository repository;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: _spotlightBacking,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Hero(
              tag: 'gallery-artwork-${artwork.activityId}',
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 360,
                  maxHeight: 360,
                ),
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
                    semanticLabel: _artworkTitle(artwork),
                    placeholderBuilder: (_) => const SizedBox(
                      width: 240,
                      height: 240,
                      child: ColoredBox(
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
          const SizedBox(height: AppSpacing.lg),
          _Plaque(
            title: _artworkTitle(artwork),
            date: _formatDate(artwork.completedAt ?? artwork.startedAt),
            large: true,
          ),
        ],
      ),
    ),
  );
}

class _HallChevron extends StatelessWidget {
  const _HallChevron({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
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
  );
}

class _DocentLine extends StatelessWidget {
  const _DocentLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/characters/costumes/dodam_base.png',
          width: 34,
          height: 34,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '도담이: $message',
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
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
      children: [
        Semantics(
          button: true,
          label: '뒤로 가기',
          child: _TapScale(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
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
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 84),
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

String _artworkTitle(ActivitySummaryDto artwork) {
  final title = artwork.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  return artwork.drawingType.name;
}

String _formatDate(String iso) {
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
