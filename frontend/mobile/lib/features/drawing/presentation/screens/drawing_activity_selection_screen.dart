import 'package:flutter/material.dart';

import '../../../../../app/router/app_router.dart';
import '../../../../../app/router/app_routes.dart';
import '../../../../../design_system/design_system.dart';
import '../../application/drawing_session_start_controller.dart';
import '../../data/dto/drawing_dtos.dart';
import '../../domain/pending_htp_photo.dart';
import '../../domain/repositories/drawing_repository.dart';
import 'htp_photo_precapture_screen.dart';
import 'input_method_select_screen.dart';

enum _ExistingActivityChoice { resume, startNew }

/// 보호자가 아동에게 시작할 HTP 또는 그림일기 활동을 선택하는 화면이다.
class DrawingActivitySelectionScreen extends StatefulWidget {
  const DrawingActivitySelectionScreen({
    required this.childId,
    required this.repository,
    required this.replaceActive,
    this.initialActivityCode,
    this.completionSnapshotProvider,
    this.htpPhotoUploadEnabled = false,
    this.pendingHtpPhotoStore,
    super.key,
  });

  final int childId;
  final DrawingRepository repository;
  final bool replaceActive;
  final String? initialActivityCode;
  final Future<BinaryUploadDto?> Function()? completionSnapshotProvider;
  final bool htpPhotoUploadEnabled;

  /// HTP 선촬영 사진 보관 저장소(S15P11B209-872). 주입하면 "사진으로
  /// 시작하기"가 집·나무·사람을 미리 촬영하는 배치 흐름을 시작한다.
  final PendingHtpPhotoStore? pendingHtpPhotoStore;

  @override
  State<DrawingActivitySelectionScreen> createState() =>
      _DrawingActivitySelectionScreenState();
}

class _DrawingActivitySelectionScreenState
    extends State<DrawingActivitySelectionScreen> {
  late Future<List<DrawingTypeDto>> _typesFuture;
  DrawingTypeDto? _selected;
  bool _isStarting = false;
  bool _isResolvingEntry = false;
  bool _entryResolved = false;
  bool _replaceActive = false;
  Object? _entryError;
  Object? _directStartError;
  bool _directStartScheduled = false;

  @override
  void initState() {
    super.initState();
    _replaceActive = widget.replaceActive;
    _typesFuture = _loadTypes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resolveEntry();
    });
  }

  /// 활동 선택 전에 진행 중 활동을 확인해 이어하기 또는 새 활동 교체를 결정한다.
  Future<void> _resolveEntry() async {
    if (_isResolvingEntry || _entryResolved) return;
    setState(() {
      _isResolvingEntry = true;
      _entryError = null;
    });
    try {
      final controller = DrawingSessionStartController(
        repository: widget.repository,
      );
      final activeSession = await controller.findActiveSession(
        childId: widget.childId,
      );
      if (!mounted) return;
      if (activeSession == null) {
        setState(() => _entryResolved = true);
        return;
      }

      final choice = await _showExistingActivityDialog();
      if (!mounted || choice == null) return;
      if (choice == _ExistingActivityChoice.resume) {
        // 이어 그리기는 아동 홈을 거치지 않고 진행 중이던 캔버스를 바로 연다.
        await Navigator.of(context).pushReplacementNamed(
          AppRoutes.childModeHome(widget.childId.toString()),
          arguments: ChildModeHomeRouteArguments(
            preparedResolution: controller.resume(activeSession),
            autoStartPrepared: true,
          ),
        );
        return;
      }
      setState(() {
        _replaceActive = true;
        _entryResolved = true;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _entryError = error);
    } finally {
      if (mounted) setState(() => _isResolvingEntry = false);
    }
  }

  Future<_ExistingActivityChoice?> _showExistingActivityDialog() =>
      showDialog<_ExistingActivityChoice>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
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
                    style: Theme.of(dialogContext).textTheme.bodyLarge
                        ?.copyWith(color: AppColors.inkMuted, height: 1.45),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton(
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(_ExistingActivityChoice.resume),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.leaf,
                      ),
                      child: const Text('이어 그리기'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(_ExistingActivityChoice.startNew),
                      child: const Text('새로 그리기'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Future<List<DrawingTypeDto>> _loadTypes() async {
    final page = await widget.repository.getDrawingTypes(
      childId: widget.childId,
    );
    final supported =
        page.content
            .where((type) => type.code == 'HTP' || type.code == 'ART_DIARY')
            .toList()
          ..sort(
            (left, right) => left.displayOrder.compareTo(right.displayOrder),
          );
    return supported;
  }

  Future<void> _startSelected() async {
    final selected = _selected;
    if (selected == null || _isStarting) return;
    setState(() => _isStarting = true);
    try {
      DrawingSessionResolution? resolution;
      // 선촬영 배치로 시작하면 HOUSE는 아직 사진 입력 단계라, 홈에서 자동으로
      // 이어 열어 보관 사진을 자동 업로드하게 한다(S15P11B209-872).
      var autoStartBatch = false;
      if (selected.code == 'HTP') {
        final htpResult = await Navigator.of(context).push<Object?>(
          MaterialPageRoute(
            builder: (_) => InputMethodSelectScreen(
              childId: widget.childId,
              drawingTypeId: selected.drawingTypeId,
              title: selected.name,
              description: selected.guideText ?? '집·나무·사람을 차례로 그려요.',
              icon: Icons.home_work_rounded,
              accentColor: AppColors.tangerine,
              repository: widget.repository,
              replaceActive: _replaceActive,
              htpPhotoUploadEnabled: widget.htpPhotoUploadEnabled,
              htpPhotoBatchEnabled: widget.pendingHtpPhotoStore != null,
            ),
          ),
        );
        if (!mounted) return;
        if (htpResult is HtpPhotoBatchRequested) {
          final captured = await runHtpPhotoPrecapture(
            context: context,
            childId: widget.childId,
            store: widget.pendingHtpPhotoStore!,
          );
          if (!captured || !mounted) return;
          resolution = await DrawingSessionStartController(
            repository: widget.repository,
          ).createHtpAssessment(
            childId: widget.childId,
            replaceActive: _replaceActive,
            inputMethod: 'UPLOAD',
          );
          autoStartBatch = true;
        } else if (htpResult is DrawingSessionResolution) {
          resolution = htpResult;
        }
      } else {
        resolution = await DrawingSessionStartController(
          repository: widget.repository,
        ).createSelectedSession(
          childId: widget.childId,
          drawingTypeId: selected.drawingTypeId,
          replaceActive: _replaceActive,
          inputMethod: 'CANVAS',
        );
      }
      if (!mounted) return;
      if (resolution == null) {
        if (widget.initialActivityCode != null) {
          Navigator.of(context).pop();
        }
        return;
      }
      await Navigator.of(context).pushReplacementNamed(
        AppRoutes.childModeHome(widget.childId.toString()),
        arguments: ChildModeHomeRouteArguments(
          preparedResolution: resolution,
          // 사진 업로드·완료까지 끝난 세션(대화 단계)이나 선촬영 배치의 첫 주제는
          // 홈에서 자동으로 이어 연다. 캔버스 최초 선택은 아이가 직접 시작한다
          // (S15P11B209-834·872).
          autoStartPrepared:
              autoStartBatch ||
              (resolution.isUploadInput &&
                  resolution.target == DrawingResolutionTarget.conversation),
        ),
      );
    } on Object {
      if (mounted) {
        if (widget.initialActivityCode != null) {
          setState(() => _directStartError = StateError('활동 시작 실패'));
        } else {
          showAppMessage(
            context,
            message: '활동을 시작하지 못했어요. 잠시 후 다시 시도해 주세요.',
            type: AppMessageType.error,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  void _scheduleDirectStart(List<DrawingTypeDto> types) {
    if (_directStartScheduled || _isStarting) return;
    final targetCode = widget.initialActivityCode;
    if (targetCode == null) return;
    DrawingTypeDto? target;
    for (final type in types) {
      if (type.code == targetCode) {
        target = type;
        break;
      }
    }
    if (target == null) {
      _directStartError = StateError('지원하는 활동을 찾지 못했습니다.');
      return;
    }
    _directStartScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() {
        _selected = target;
        _directStartError = null;
      });
      await _startSelected();
      if (!mounted) return;
      if (_selected != null && !_isStarting) {
        setState(() => _directStartScheduled = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.childCanvas,
    appBar: AppTopBar(
      title: '어떤 활동을 해볼까요?',
      onBack: () => Navigator.of(context).pop(),
    ),
    body: SafeArea(
      child: !_entryResolved
          ? _entryError == null
                ? const AppLoadingView(message: '그리던 활동이 있는지 확인하고 있어요')
                : AppErrorView(
                    title: '진행 중인 활동을 확인하지 못했어요',
                    message: '잠시 후 다시 시도해 주세요.',
                    retryLabel: '다시 시도',
                    onRetry: _resolveEntry,
                  )
          : FutureBuilder<List<DrawingTypeDto>>(
              future: _typesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return AppErrorView(
                    title: '활동을 불러오지 못했어요',
                    message: '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
                    retryLabel: '다시 시도',
                    onRetry: () => setState(() => _typesFuture = _loadTypes()),
                  );
                }
                final types = snapshot.data ?? const [];
                if (types.isEmpty) {
                  return const AppEmptyView(
                    title: '지금 시작할 수 있는 활동이 없어요',
                    message: '활동이 준비되면 다시 알려드릴게요.',
                  );
                }
                if (widget.initialActivityCode != null) {
                  if (_directStartError != null) {
                    return AppErrorView(
                      title: '활동을 시작하지 못했어요',
                      message: '잠시 후 다시 시도해 주세요.',
                      retryLabel: '다시 시도',
                      onRetry: () => setState(() {
                        _directStartError = null;
                        _directStartScheduled = false;
                      }),
                    );
                  }
                  _scheduleDirectStart(types);
                  return const AppLoadingView(
                    message: '집·나무·사람 그림 활동을 준비하고 있어요',
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '하고 싶은 활동을 하나 골라 주세요.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Expanded(
                        child: Row(
                          children: [
                            for (
                              var index = 0;
                              index < types.length;
                              index++
                            ) ...[
                              Expanded(
                                child: _ActivityCard(
                                  type: types[index],
                                  selected:
                                      _selected?.drawingTypeId ==
                                      types[index].drawingTypeId,
                                  onTap: () =>
                                      setState(() => _selected = types[index]),
                                ),
                              ),
                              if (index != types.length - 1)
                                const SizedBox(width: AppSpacing.lg),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        height: 64,
                        child: FilledButton(
                          onPressed: _selected == null || _isStarting
                              ? null
                              : _startSelected,
                          child: Text(_isStarting ? '준비하고 있어요…' : '다음'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    ),
  );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final DrawingTypeDto type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isHtp = type.code == 'HTP';
    return Semantics(
      button: true,
      selected: selected,
      label: type.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? AppColors.leaf : AppColors.outline,
              width: selected ? 3 : 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x1F2F7D4B),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isHtp ? Icons.home_work_rounded : Icons.menu_book_rounded,
                size: 82,
                color: isHtp ? AppColors.tangerine : AppColors.leaf,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                type.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                type.guideText ??
                    (isHtp ? '집·나무·사람을 차례로 그려요.' : '오늘 기억에 남는 일을 그림으로 남겨요.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
