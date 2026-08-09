import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/dodam_costume.dart';

/// 그림·AI 대화에서 활동 시작 시 확정한 도담이 snapshot을 표시한다.
///
/// 코드→asset·이름 매핑은 [DodamCostume] 한 곳만 사용한다. 선택 asset decode가
/// 실패하면 BASE를 한 번 시도하고, BASE도 읽지 못하면 안전한 장식 placeholder를
/// 남겨 질문 chip이나 Canvas gesture를 막지 않는다.
final class DodamCompanionAvatar extends StatelessWidget {
  const DodamCompanionAvatar({
    required this.companion,
    this.compact = false,
    this.semanticsLabel,
    super.key,
  });

  final DodamCostume companion;
  final bool compact;

  /// null이면 상위 질문 semantics가 이름을 한 번만 읽도록 장식 이미지로 둔다.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      key: const ValueKey('dodami-character'),
      width: compact ? 64 : 124,
      height: compact ? 64 : 124,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(color: AppColors.tangerineSoft, width: 4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Transform.scale(
          scale: 1.35,
          child: _CompanionAsset(companion: companion),
        ),
      ),
    );
    final label = semanticsLabel;
    if (label == null) return ExcludeSemantics(child: avatar);
    return Semantics(
      image: true,
      label: label,
      child: ExcludeSemantics(child: avatar),
    );
  }
}

final class _CompanionAsset extends StatelessWidget {
  const _CompanionAsset({required this.companion});

  final DodamCostume companion;

  @override
  Widget build(BuildContext context) => Image.asset(
    companion.asset,
    key: ValueKey('dodam-companion-image-${companion.code}'),
    fit: BoxFit.cover,
    alignment: Alignment.topCenter,
    filterQuality: FilterQuality.high,
    errorBuilder: (_, _, _) {
      if (companion == DodamCostume.base) return const _CompanionPlaceholder();
      return Image.asset(
        DodamCostume.base.asset,
        key: const ValueKey('dodam-companion-image-fallback-BASE'),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => const _CompanionPlaceholder(),
      );
    },
  );
}

final class _CompanionPlaceholder extends StatelessWidget {
  const _CompanionPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    key: ValueKey('dodam-companion-image-placeholder'),
    color: AppColors.tangerineSoft,
    child: Center(
      child: Icon(
        Icons.sentiment_satisfied_alt_rounded,
        color: AppColors.tangerine,
        size: 36,
      ),
    ),
  );
}
