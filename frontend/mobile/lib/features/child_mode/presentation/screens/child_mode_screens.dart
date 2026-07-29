import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/app_router.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../design_system/design_system.dart';
import '../../../activity/presentation/screens/activity_screens.dart';
import '../../../child/data/dto/child_dtos.dart';
import '../../../drawing/application/drawing_session_start_controller.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';
import '../../../drawing/domain/repositories/drawing_repository.dart';
import '../widgets/activity_guide_dialog.dart';

enum _ActivityLoadStatus { loading, loaded, empty, error }

enum _DrawingStartChoice { resume, startNew }

/// 그림 유형 코드별 카드·안내 팝업 아이콘/강조색.
///
/// 백엔드가 새 activityType(예: 462 HTP)을 추가해도 이 표에 항목만 더하면
/// 되고, 목록에 없는 코드는 기본값(팔레트 아이콘·leaf색)으로 표시한다.
(IconData, Color) _visualForDrawingType(String code) => switch (code) {
  'HTP' => (Icons.home_work_rounded, AppColors.leaf),
  'ART_DIARY' => (Icons.menu_book_rounded, AppColors.tangerine),
  _ => (Icons.palette_rounded, AppColors.leaf),
};

/// 활동 소개 문구는 서버 `guideText`를 우선 쓰고, 비어 있으면 아동 친화적인
/// 임시 문구로 대체한다(제품 문구 확정 전 임시 가정 — 최종 보고 참고).
String _descriptionForDrawingType(DrawingTypeDto type) {
  final guideText = type.guideText?.trim();
  if (guideText != null && guideText.isNotEmpty) return guideText;
  return '그리고 싶은 것을 자유롭게 그려 보자!';
}

class ChildModeHomeScreen extends StatefulWidget {
  const ChildModeHomeScreen({
    required this.child,
    required this.drawingRepository,
    this.completionSnapshotProvider,
    super.key,
  });

  final ChildSummaryDto child;
  final DrawingRepository drawingRepository;
  final Future<BinaryUploadDto?> Function()? completionSnapshotProvider;

  @override
  State<ChildModeHomeScreen> createState() => _ChildModeHomeScreenState();
}

class _ChildModeHomeScreenState extends State<ChildModeHomeScreen> {
  _ActivityLoadStatus _status = _ActivityLoadStatus.loading;
  List<DrawingTypeDto> _drawingTypes = const [];

  /// 안내 팝업이 열려 있거나 세션 시작 요청 중인 활동의 id.
  ///
  /// null이 아니면 다른 카드 탭을 막아 팝업 중복 표시와 중복 세션 생성을
  /// 함께 방지한다.
  int? _startingDrawingTypeId;

  /// 활성 세션 유무를 확인하는 짧은 네트워크 대기 동안만 켜진다.
  ///
  /// 안내 팝업이나 이어 그리기 다이얼로그가 뜨면 그 안의 버튼이 로딩을
  /// 대신 표시하므로, 그 뒤로는 카드에서 계속 스피너를 돌리지 않는다
  /// (그렇지 않으면 팝업이 열려 있는 동안 카드가 영원히 로딩 상태로 남는다).
  bool _checkingActiveSession = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDrawingTypes());
  }

  Future<void> _loadDrawingTypes() async {
    setState(() => _status = _ActivityLoadStatus.loading);
    try {
      final page = await widget.drawingRepository.getDrawingTypes(
        childId: widget.child.childId,
      );
      if (!mounted) return;
      final sorted =
          page.content
              .where((type) => type.code == 'HTP' || type.code == 'ART_DIARY')
              .toList()
            ..sort(
              (left, right) => left.displayOrder.compareTo(right.displayOrder),
            );
      setState(() {
        _drawingTypes = sorted;
        _status = sorted.isEmpty
            ? _ActivityLoadStatus.empty
            : _ActivityLoadStatus.loaded;
      });
    } on Object {
      if (mounted) setState(() => _status = _ActivityLoadStatus.error);
    }
  }

  Future<_DrawingStartChoice?> _showDrawingStartDialog() {
    return showDialog<_DrawingStartChoice>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 30, 32, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: AppColors.childCanvas,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('✏️', style: TextStyle(fontSize: 42)),
                ),
                const SizedBox(height: 22),
                Text(
                  '그리던 그림이 있어요',
                  style: Theme.of(dialogContext).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                Text(
                  '그림을 그리다 멈췄어요.\n이어서 그릴까요?',
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                    color: AppColors.inkMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: FilledButton(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_DrawingStartChoice.resume),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.leaf,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      '이어 그리기',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_DrawingStartChoice.startNew),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: AppColors.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      '새로 그리기',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
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

  Future<void> _selectActivity(DrawingTypeDto type) async {
    if (_startingDrawingTypeId != null) return;
    setState(() {
      _startingDrawingTypeId = type.drawingTypeId;
      _checkingActiveSession = true;
    });
    try {
      final controller = DrawingSessionStartController(
        repository: widget.drawingRepository,
      );
      final activeSession = await controller.findActiveSession(
        childId: widget.child.childId,
      );
      if (!mounted) return;
      setState(() => _checkingActiveSession = false);

      DrawingSessionResolution? resolution;
      if (activeSession != null) {
        final choice = await _showDrawingStartDialog();
        if (choice == null || !mounted) return;
        if (choice == _DrawingStartChoice.startNew) {
          resolution = await _createSelectedActivity(
            controller: controller,
            type: type,
            replaceActive: true,
          );
        } else {
          resolution = controller.resume(activeSession);
          if (resolution.activityContext.isHtp &&
              resolution.currentStage == 'COMPLETED') {
            await AppNavigation.pushNamed(
              context,
              AppRoutes.emotionSelect(widget.child.childId.toString()),
              arguments: EmotionSelectRouteArguments(
                sessionId: resolution.sessionId,
                repository: widget.drawingRepository,
                conversationId: null,
                conversationAlreadyEnded: true,
                conversationEndRepository: null,
                conversationEndIdempotencyKey: null,
                conversationEndRequest: null,
                lastQuestionMessageId: null,
                idempotencyKeyProvider: null,
                activityContext: resolution.activityContext,
              ),
            );
            return;
          }
        }
      } else {
        final (icon, accentColor) = _visualForDrawingType(type.code);
        resolution = await showActivityGuideDialog<DrawingSessionResolution>(
          context: context,
          title: type.name,
          description: _descriptionForDrawingType(type),
          icon: icon,
          accentColor: accentColor,
          onStart: () =>
              _createSelectedActivity(controller: controller, type: type),
        );
      }
      if (resolution == null || !mounted) return;
      await AppNavigation.pushNamed(
        context,
        AppRoutes.drawing(widget.child.childId.toString()),
        arguments: DrawingRouteArguments(
          sessionId: resolution.sessionId,
          repository: widget.drawingRepository,
          completionSnapshotProvider: widget.completionSnapshotProvider,
          resumeConversation: !resolution.isDrawingStage,
          activityContext: resolution.activityContext,
        ),
      );
    } on Object {
      if (mounted) {
        showAppMessage(
          context,
          message: '그림 활동을 시작하지 못했어요. 다시 시도해 주세요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _startingDrawingTypeId = null;
          _checkingActiveSession = false;
        });
      }
    }
  }

  Future<DrawingSessionResolution> _createSelectedActivity({
    required DrawingSessionStartController controller,
    required DrawingTypeDto type,
    bool replaceActive = false,
  }) => type.code == 'HTP'
      ? controller.createHtpAssessment(
          childId: widget.child.childId,
          replaceActive: replaceActive,
        )
      : controller.createSelectedSession(
          childId: widget.child.childId,
          drawingTypeId: type.drawingTypeId,
          replaceActive: replaceActive,
          inputMethod: 'CANVAS',
        );

  Widget _buildActivitySection() {
    switch (_status) {
      case _ActivityLoadStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: AppLoadingView(
            message: '어떤 활동이 있는지 불러오고 있어요',
            childFriendly: true,
          ),
        );
      case _ActivityLoadStatus.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: AppErrorView(
            title: '활동을 불러오지 못했어요',
            message: '잠시 후 다시 시도해 주세요.',
            onRetry: () => unawaited(_loadDrawingTypes()),
            childFriendly: true,
          ),
        );
      case _ActivityLoadStatus.empty:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: AppEmptyView(
            title: '아직 준비된 그림 활동이 없어요',
            message: '조금 있다가 다시 확인해 볼까?',
            childFriendly: true,
          ),
        );
      case _ActivityLoadStatus.loaded:
        return LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 700;
            final cardWidth = narrow ? constraints.maxWidth : 320.0;
            final history = _ChildActionCard(
              key: const ValueKey('history-action'),
              icon: Icons.collections_bookmark_outlined,
              title: '지난 그림 보기',
              description: '다음 단계에서 만날 수 있어요',
              color: AppColors.lavender,
            );
            return Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.md,
              children: [
                SizedBox(width: cardWidth, child: history),
                for (final type in _drawingTypes)
                  SizedBox(
                    width: cardWidth,
                    child: _ChildActionCard(
                      key: ValueKey('activity-${type.drawingTypeId}'),
                      icon: _visualForDrawingType(type.code).$1,
                      title: type.name,
                      description: _descriptionForDrawingType(type),
                      color: _visualForDrawingType(type.code).$2,
                      // 활성 세션 확인 중일 때만 스피너를 보여준다. 그 뒤로는
                      // 안내 팝업이나 이어 그리기 다이얼로그가 로딩을 맡는다.
                      isLoading:
                          _checkingActiveSession &&
                          _startingDrawingTypeId == type.drawingTypeId,
                      onTap: _startingDrawingTypeId == null
                          ? () => unawaited(_selectActivity(type))
                          : null,
                    ),
                  ),
              ],
            );
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      backgroundColor: AppColors.childCanvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: '길게 눌러 보호자 화면으로 돌아가기',
                  child: GestureDetector(
                    key: const ValueKey('guardian-return-hold'),
                    onLongPress: () => AppRouter.goGuardianHome(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            color: AppColors.inkMuted,
                            size: 20,
                          ),
                          SizedBox(width: AppSpacing.xs),
                          Text(
                            '보호자 화면',
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
                child: Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSizes.wideContentMaxWidth,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 132,
                            height: 132,
                            decoration: const BoxDecoration(
                              color: AppColors.tangerineSoft,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.emoji_nature_rounded,
                              size: 72,
                              color: AppColors.tangerine,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            '${widget.child.nickname}, 오늘은 무엇을 그려 볼까?',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(
                            '그리고 싶은 것을 천천히 골라도 괜찮아!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          _buildActivitySection(),
                        ],
                      ),
                    ),
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

class _ChildActionCard extends StatelessWidget {
  const _ChildActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    this.isLoading = false,
    this.onTap,
    super.key,
  });
  final IconData icon;
  final String title, description;
  final Color color;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    enabled: onTap != null,
    label: isLoading ? '$title, 활동을 준비하는 중' : '$title. $description',
    child: ExcludeSemantics(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 180,
              minWidth: AppSizes.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading)
                    const SizedBox.square(
                      dimension: 58,
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: CircularProgressIndicator(
                          color: AppColors.tangerine,
                        ),
                      ),
                    )
                  else
                    Icon(
                      icon,
                      size: 58,
                      color: onTap == null ? AppColors.disabled : color,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
