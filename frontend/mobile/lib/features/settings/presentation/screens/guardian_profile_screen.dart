import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../auth/auth.dart';

typedef GuardianProfileLoad = Future<AuthenticatedUser> Function();
typedef GuardianProfileUpdate =
    Future<AuthenticatedUser> Function(String nickname);

/// USER-01/03 보호자 프로필 조회·수정 화면.
class GuardianProfileScreen extends StatefulWidget {
  const GuardianProfileScreen({
    required this.initialUser,
    required this.loadProfile,
    required this.updateProfile,
    super.key,
  });

  final AuthenticatedUser? initialUser;
  final GuardianProfileLoad loadProfile;
  final GuardianProfileUpdate updateProfile;

  @override
  State<GuardianProfileScreen> createState() => _GuardianProfileScreenState();
}

class _GuardianProfileScreenState extends State<GuardianProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameController;
  AuthenticatedUser? _user;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
    _nicknameController = TextEditingController(
      text: widget.initialUser?.nickname ?? '',
    );
    _load();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final user = await widget.loadProfile();
      if (!mounted) return;
      setState(() {
        _user = user;
        _nicknameController.text = user.nickname ?? '';
      });
    } on Object {
      if (mounted) setState(() => _loadError = '내 정보를 불러오지 못했어요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    try {
      final user = await widget.updateProfile(_nicknameController.text);
      if (!mounted) return;
      setState(() => _user = user);
      showAppMessage(context, message: '내 정보를 저장했어요.');
    } on Object {
      if (mounted) {
        showAppMessage(
          context,
          message: '내 정보를 저장하지 못했어요. 다시 시도해 주세요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '내 정보 관리',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      child: _isLoading && _user == null
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && _user == null
          ? _ProfileLoadError(message: _loadError!, onRetry: _load)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProfileHeader(user: _user),
                        const SizedBox(height: AppSpacing.lg),
                        _ProfileFormCard(
                          user: _user,
                          nicknameController: _nicknameController,
                        ),
                        if (_loadError != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            '최신 정보를 불러오지 못해 저장된 정보를 표시하고 있어요.',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton(
                          onPressed: _isSaving ? null : _save,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(60),
                            backgroundColor: AppColors.leaf,
                          ),
                          child: _isSaving
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('저장하기'),
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AuthenticatedUser? user;

  @override
  Widget build(BuildContext context) {
    final imageUrl = user?.profileImageUrl;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: AppColors.leafSoft,
            backgroundImage: imageUrl == null || imageUrl.isEmpty
                ? null
                : NetworkImage(imageUrl),
            child: imageUrl == null || imageUrl.isEmpty
                ? const Icon(Icons.eco_rounded, size: 40, color: AppColors.leaf)
                : null,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user?.nickname ?? '보호자님', style: AppTypography.titleLg),
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  '프로필 이미지는 현재 조회만 가능해요.',
                  style: AppTypography.bodySm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileFormCard extends StatelessWidget {
  const _ProfileFormCard({
    required this.user,
    required this.nicknameController,
  });

  final AuthenticatedUser? user;
  final TextEditingController nicknameController;

  @override
  Widget build(BuildContext context) {
    final provider = switch (user?.provider) {
      AuthProvider.kakao => '카카오',
      AuthProvider.google => '구글',
      AuthProvider.naver => '네이버',
      null => '소셜',
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('기본 정보', style: AppTypography.titleMd),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            key: const ValueKey('guardian-profile-nickname'),
            controller: nicknameController,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: '닉네임',
              hintText: '사용할 닉네임을 입력해 주세요',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final nickname = value?.trim() ?? '';
              if (nickname.isEmpty) return '닉네임을 입력해 주세요.';
              if (nickname.length > 50) return '닉네임은 50자 이하로 입력해 주세요.';
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _ReadOnlyField(label: '이메일', value: user?.email ?? '등록된 이메일 없음'),
          const SizedBox(height: AppSpacing.md),
          _ReadOnlyField(label: '연결 계정', value: '$provider 계정'),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '소셜 로그인 계정과 이메일은 이 화면에서 변경할 수 없어요.',
            style: AppTypography.bodySm,
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: AppColors.canvas,
    ),
    child: Text(value, style: AppTypography.body),
  );
}

class _ProfileLoadError extends StatelessWidget {
  const _ProfileLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: AppColors.error,
          size: 48,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(message, style: AppTypography.body),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    ),
  );
}
