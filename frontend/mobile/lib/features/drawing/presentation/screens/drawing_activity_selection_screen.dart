import 'package:flutter/material.dart';

import '../../../../../app/router/app_router.dart';
import '../../../../../app/router/app_routes.dart';
import '../../../../../design_system/design_system.dart';
import '../../application/drawing_session_start_controller.dart';
import '../../data/dto/drawing_dtos.dart';
import '../../domain/repositories/drawing_repository.dart';

/// 보호자가 아동에게 시작할 HTP 또는 그림일기 활동을 선택하는 화면이다.
class DrawingActivitySelectionScreen extends StatefulWidget {
  const DrawingActivitySelectionScreen({
    required this.childId,
    required this.repository,
    required this.replaceActive,
    this.completionSnapshotProvider,
    super.key,
  });

  final int childId;
  final DrawingRepository repository;
  final bool replaceActive;
  final Future<BinaryUploadDto?> Function()? completionSnapshotProvider;

  @override
  State<DrawingActivitySelectionScreen> createState() =>
      _DrawingActivitySelectionScreenState();
}

class _DrawingActivitySelectionScreenState
    extends State<DrawingActivitySelectionScreen> {
  late Future<List<DrawingTypeDto>> _typesFuture;
  DrawingTypeDto? _selected;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _typesFuture = _loadTypes();
  }

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
      final controller = DrawingSessionStartController(
        repository: widget.repository,
      );
      final resolution = selected.code == 'HTP'
          ? await controller.createHtpAssessment(
              childId: widget.childId,
              replaceActive: widget.replaceActive,
            )
          : await controller.createSelectedSession(
              childId: widget.childId,
              drawingTypeId: selected.drawingTypeId,
              replaceActive: widget.replaceActive,
            );
      if (!mounted) return;
      await Navigator.of(context).pushReplacementNamed(
        AppRoutes.drawing(widget.childId.toString()),
        arguments: DrawingRouteArguments(
          sessionId: resolution.sessionId,
          repository: widget.repository,
          completionSnapshotProvider: widget.completionSnapshotProvider,
          activityContext: resolution.activityContext,
        ),
      );
    } on Object {
      if (mounted) {
        showAppMessage(
          context,
          message: '활동을 시작하지 못했어요. 잠시 후 다시 시도해 주세요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.childCanvas,
    appBar: AppTopBar(
      title: '어떤 활동을 해볼까요?',
      onBack: () => Navigator.of(context).pop(),
    ),
    body: SafeArea(
      child: FutureBuilder<List<DrawingTypeDto>>(
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
                      for (var index = 0; index < types.length; index++) ...[
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
