import 'package:flutter/material.dart';

import '../../../../app/widgets/app_failure_view.dart';
import '../../../../design_system/design_system.dart';
import '../../application/notification_settings_controller.dart';
import '../../domain/repositories/notification_settings_repository.dart';

/// 설정 > 알림 설정 (S15P11B209-455).
///
/// 알림 수신 여부 네 가지를 조회해 보여주고 한 번에 저장한다
/// (`GET`·`PATCH /users/me/notification-settings`).
///
/// 설계에서 정한 것
/// - **토글마다 저장하지 않는다.** 계약이 네 필드 전체 교체(`PATCH` 이지만 부분
///   수정 아님)라, 토글마다 보내면 요청이 네 배가 되고 중간 실패 시 화면과 서버가
///   어긋난다. 편집값을 모아 "저장"에서 한 번 보낸다.
/// - **끈 항목이 무엇을 뜻하는지 화면에서 말한다.** 알림을 끄면 그 알림은 기기로도
///   오지 않고 알림함에도 쌓이지 않는다고 오해할 수 있다. 실제로 서버가 어디까지
///   막는지는 계약에 규정돼 있지 않아, 화면은 "받지 않기로 설정"이라고만 말하고
///   삭제·보관 동작을 약속하지 않는다.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({required this.repository, super.key});

  final NotificationSettingsRepository repository;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final NotificationSettingsController _controller =
      NotificationSettingsController(widget.repository);

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final succeeded = await _controller.save();
    if (!mounted) return;
    if (succeeded) {
      showAppMessage(
        context,
        message: '알림 설정을 저장했어요.',
        type: AppMessageType.success,
      );
      return;
    }
    final message = _controller.saveFailureMessage;
    if (message != null) {
      showAppMessage(context, message: message, type: AppMessageType.error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '알림 설정',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => switch (_controller.status) {
          NotificationSettingsStatus.loading => const AppLoadingView(
            key: ValueKey('notification-settings-loading'),
            message: '알림 설정을 불러오고 있어요',
          ),
          NotificationSettingsStatus.error => AppFailureView(
            title: '알림 설정을 불러오지 못했어요',
            failure: _controller.error,
            onRetry: _controller.load,
          ),
          NotificationSettingsStatus.ready => _NotificationSettingsBody(
            controller: _controller,
            onSave: _save,
          ),
        },
      ),
    ),
  );
}

class _NotificationSettingsBody extends StatelessWidget {
  const _NotificationSettingsBody({
    required this.controller,
    required this.onSave,
  });

  final NotificationSettingsController controller;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    if (settings == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionCard(
                title: '아이 활동 알림',
                description: '아이가 그림 활동을 마치고 분석이 끝났을 때 알려드려요.',
                child: _SettingSwitch(
                  switchKey: const ValueKey('notification-settings-analysis'),
                  title: '분석 완료 알림',
                  description: '그림 심리 상담 리포트가 준비되면 알려드려요.',
                  value: settings.analysisCompleted,
                  isEnabled: !controller.isSaving,
                  onChanged: controller.setAnalysisCompleted,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionCard(
                title: '서비스 알림',
                description: '도담을 쓰는 데 필요한 소식이에요.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingSwitch(
                      switchKey: const ValueKey(
                        'notification-settings-service-notice',
                      ),
                      title: '서비스 공지',
                      description: '점검·약관 변경처럼 꼭 알아야 하는 소식이에요.',
                      value: settings.serviceNotice,
                      isEnabled: !controller.isSaving,
                      onChanged: controller.setServiceNotice,
                    ),
                    const Divider(height: AppSpacing.lg),
                    _SettingSwitch(
                      switchKey: const ValueKey(
                        'notification-settings-community',
                      ),
                      title: '커뮤니티 알림',
                      description: '내 글에 댓글이 달리거나 전문가 글이 올라오면 알려드려요.',
                      value: settings.community,
                      isEnabled: !controller.isSaving,
                      onChanged: controller.setCommunity,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionCard(
                title: '마케팅 정보',
                description: '받지 않아도 서비스를 쓰는 데 아무 지장이 없어요.',
                child: _SettingSwitch(
                  switchKey: const ValueKey('notification-settings-marketing'),
                  title: '혜택·이벤트 소식',
                  description: '새 기능이나 이벤트 안내를 받아요.',
                  value: settings.marketing,
                  isEnabled: !controller.isSaving,
                  onChanged: controller.setMarketing,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: AppIconSize.sm,
                    color: AppColors.inkMuted,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      '기기 자체의 알림 권한을 꺼 두면 여기서 켜 두어도 알림이 오지 않아요.',
                      style: AppTypography.bodySm,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                key: const ValueKey('notification-settings-save'),
                label: '저장',
                isLoading: controller.isSaving,
                onPressed: controller.canSave ? () => onSave() : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 흰 카드 + 제목·설명 + 내용. 설정 묶음 하나를 담는다.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.titleMd),
        const SizedBox(height: AppSpacing.xxs),
        Text(description, style: AppTypography.bodySm),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    ),
  );
}

/// 알림 항목 하나의 켜기·끄기. 제목과 설명을 함께 보여준다.
///
/// 저장 중에는 [isEnabled] 가 거짓이 되어 조작을 막는다. 저장 요청이 나간 뒤에
/// 값을 더 바꾸면 화면과 서버가 어긋나기 때문이다.
class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.switchKey,
    required this.title,
    required this.description,
    required this.value,
    required this.isEnabled,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String description;
  final bool value;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.bodyStrong),
            const SizedBox(height: AppSpacing.xxs),
            Text(description, style: AppTypography.bodySm),
          ],
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      Switch(
        key: switchKey,
        value: value,
        onChanged: isEnabled ? onChanged : null,
      ),
    ],
  );
}
