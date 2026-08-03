import 'package:flutter/material.dart';

import '../../../../app/state/guardian_child_controller.dart';
import '../../../../design_system/design_system.dart';
import '../../data/dto/child_consent_dtos.dart';
import '../../data/dto/child_dtos.dart';
import '../../domain/preferred_character.dart';

class ChildRegistrationScreen extends StatefulWidget {
  const ChildRegistrationScreen({
    required this.controller,
    this.child,
    super.key,
  });

  final GuardianChildController controller;
  final ChildSummaryDto? child;

  @override
  State<ChildRegistrationScreen> createState() =>
      _ChildRegistrationScreenState();
}

class _ChildRegistrationScreenState extends State<ChildRegistrationScreen> {
  final _nicknameController = TextEditingController();
  DateTime? _birthDate;
  String _relationshipType = 'MOTHER';
  String _preferredCharacter = 'BASE';
  String _questionDifficulty = 'PRESCHOOL';
  bool _submitted = false;
  Set<int> _acknowledgedDeclinedTermIds = const {};
  bool get _isEditing => widget.child != null;

  /// 아동 대상 약관의 동의 여부. 기본값은 미동의이며 사용자가 직접 켜야 한다.
  final Map<int, bool> _consentAgreed = {};

  static const _characters = [
    ('BASE', '🌱'),
    ('PRINCESS', '👸'),
    ('DINO', '🦖'),
    ('OCTOPUS', '🐙'),
  ];

  static const _relationships = {
    'MOTHER': '어머니',
    'FATHER': '아버지',
    'GRANDPARENT': '조부모',
    'GUARDIAN': '보호자',
    'OTHER': '기타',
  };

  static const _difficulties = [
    ('PRESCHOOL', '유아형 (만 4–6세)', '짧고 쉬운 말로 천천히 물어봐요', '🌱'),
    ('LOWER_ELEMENTARY', '초등 저학년형 (만 7–9세)', '생각을 조금 더 끌어내는 질문을 해요', '🌿'),
    ('UPPER_ELEMENTARY', '초등 고학년형 (만 10–12세)', '구체적인 이야기와 선택지를 함께 제시해요', '☘️'),
  ];

  @override
  void initState() {
    super.initState();
    final child = widget.child;
    if (child != null) {
      _nicknameController.text = child.nickname;
      _birthDate = DateTime.tryParse(child.birthDate);
      _relationshipType = child.relationshipType;
      _preferredCharacter = normalizePreferredCharacter(
        child.preferredCharacter,
      );
      _questionDifficulty = child.questionDifficulty;
    }
    widget.controller.resetRegistration();
    if (!_isEditing) widget.controller.loadChildConsentTerms();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  String? get _nicknameError {
    if (!_submitted) return null;
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return '아이 이름이나 애칭을 입력해 주세요.';
    if (nickname.length > 50) return '이름은 50자 이하로 입력해 주세요.';
    return null;
  }

  String? get _birthDateError =>
      _submitted && _birthDate == null ? '생년월일을 선택해 주세요.' : null;

  List<ConsentTermDto> get _consentTerms => widget.controller.childConsentTerms;

  /// 서버가 필수로 표시한 약관 중 미동의가 있으면 등록을 막는다.
  bool get _hasUnagreedRequiredTerm => _consentTerms.any(
    (term) => term.required && !(_consentAgreed[term.termId] ?? false),
  );

  String? get _consentError =>
      _submitted && _hasUnagreedRequiredTerm ? '필수 항목에 동의해 주세요.' : null;

  /// 체크하지 않은 항목도 WITHDRAW로 함께 보내 "묻고 거부함"을 기록한다.
  List<ConsentAgreementDto> get _consentAgreements => _consentTerms
      .map(
        (term) => (_consentAgreed[term.termId] ?? false)
            ? ConsentAgreementDto.agree(term.termId)
            : ConsentAgreementDto.withdraw(term.termId),
      )
      .toList(growable: false);

  Set<int> get _declinedOptionalTermIds => _consentTerms
      .where(
        (term) => !term.required && !(_consentAgreed[term.termId] ?? false),
      )
      .map((term) => term.termId)
      .toSet();

  String _consentRestriction(ConsentTermDto term) {
    final code = term.termCode.toUpperCase();
    if (code.contains('DRAWING') || code.contains('ANALYSIS')) {
      return '그림 데이터 분석을 사용하지 않아 그림 기반 질문과 분석 리포트 제공이 제한돼요.';
    }
    if (code.contains('VOICE') || code.contains('AUDIO')) {
      return '음성 데이터 처리를 사용하지 않아 아이가 목소리로 답할 수 없고 선택지로만 대화해요.';
    }
    if (code.contains('EXPERT') || code.contains('REPORT')) {
      return '전문가 리포트 공유를 사용하지 않아 전문가에게 활동 결과를 공유하거나 의견을 받을 수 없어요.';
    }
    return '${term.title}에 동의하지 않아 관련 기능 사용이 제한돼요.';
  }

  Future<bool> _confirmOptionalConsentRestrictions() async {
    final declinedIds = _declinedOptionalTermIds;
    if (declinedIds.isEmpty ||
        declinedIds.difference(_acknowledgedDeclinedTermIds).isEmpty &&
            _acknowledgedDeclinedTermIds.difference(declinedIds).isEmpty) {
      return true;
    }

    final declinedTerms = _consentTerms
        .where((term) => declinedIds.contains(term.termId))
        .toList(growable: false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.86,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.outline),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.warningSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.warning,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    '잠깐, 사용할 수 없는 기능이 있어요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    '선택하지 않은 약관에 따라 아래 기능이 제한돼요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Flexible(
                    child: Scrollbar(
                      thumbVisibility: declinedTerms.length > 3,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: declinedTerms.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final term = declinedTerms[index];
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.outline),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.lock_outline_rounded,
                                  color: AppColors.tangerine,
                                  size: 22,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        term.title,
                                        style: const TextStyle(
                                          color: AppColors.ink,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _consentRestriction(term),
                                        style: const TextStyle(
                                          color: AppColors.inkMuted,
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    '확인을 누르면 동의 화면으로 돌아가요. 동의하지 않으려면 선택을 유지한 채 등록하기를 다시 눌러 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const ValueKey('confirm-consent-restrictions'),
                    label: '동의 항목 다시 확인하기',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return false;
    setState(() => _acknowledgedDeclinedTermIds = declinedIds);
    return false;
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 6, now.month, now.day),
      firstDate: DateTime(now.year - 13, now.month, now.day + 1),
      lastDate: DateTime(now.year - 4, now.month, now.day),
      helpText: '아이 생년월일 선택',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (selected != null && mounted) setState(() => _birthDate = selected);
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (_nicknameError != null ||
        _birthDateError != null ||
        _consentError != null) {
      return;
    }
    if (!_isEditing && !await _confirmOptionalConsentRestrictions()) return;

    final succeeded = _isEditing
        ? await widget.controller.updateChild(
            widget.child!.childId,
            UpdateChildRequestDto(
              nickname: _nicknameController.text.trim(),
              preferredCharacter: _preferredCharacter,
              questionDifficulty: _questionDifficulty,
              responseModes: const ['VOICE'],
            ),
          )
        : await widget.controller.registerChild(
            CreateChildRequestDto(
              nickname: _nicknameController.text.trim(),
              birthDate:
                  '${_birthDate!.year.toString().padLeft(4, '0')}-'
                  '${_birthDate!.month.toString().padLeft(2, '0')}-'
                  '${_birthDate!.day.toString().padLeft(2, '0')}',
              relationshipType: _relationshipType,
              preferredCharacter: _preferredCharacter,
              questionDifficulty: _questionDifficulty,
              responseModes: const ['VOICE'],
            ),
            consentAgreements: _consentAgreements,
          );
    if (!mounted) return;
    if (succeeded) {
      // 아동은 등록됐지만 동의 기록이 실패하면 음성 답변이 거절되므로 그대로 알린다.
      if (!_isEditing && widget.controller.consentRecordError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('아이는 등록했지만 동의 저장에 실패했어요. 설정에서 다시 동의해 주세요.'),
          ),
        );
      }
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEditing
              ? '아이 정보를 수정하지 못했어요. 잠시 후 다시 시도해 주세요.'
              : '아이 등록에 실패했어요. 잠시 후 다시 시도해 주세요.',
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('아이 프로필을 삭제할까요?'),
        content: const Text('그림과 대화, 활동 기록도 함께 삭제되며 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final succeeded = await widget.controller.deleteChild(
      widget.child!.childId,
    );
    if (!mounted) return;
    if (succeeded) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('아이 프로필을 삭제하지 못했어요. 다시 시도해 주세요.')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: _isEditing ? '아이 프로필 편집' : '아이 등록',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CharacterSelector(
                    characters: _characters,
                    selected: _preferredCharacter,
                    onSelected: (value) =>
                        setState(() => _preferredCharacter = value),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppTextField(
                    key: const ValueKey('child-nickname'),
                    controller: _nicknameController,
                    label: '이름 / 애칭 *',
                    hintText: '예: 민지',
                    errorText: _nicknameError,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (!_isEditing) ...[
                    _BirthDateField(
                      value: _birthDate,
                      errorText: _birthDateError,
                      onTap: _pickBirthDate,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('guardian-relationship'),
                      initialValue: _relationshipType,
                      decoration: const InputDecoration(labelText: '아이와의 관계 *'),
                      items: _relationships.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _relationshipType = value);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  const Text(
                    '질문 난이도',
                    style: TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final difficulty in _difficulties) ...[
                    AppChoiceCard(
                      key: ValueKey('difficulty-${difficulty.$1}'),
                      label: '${difficulty.$4} ${difficulty.$2}',
                      description: difficulty.$3,
                      isSelected: _questionDifficulty == difficulty.$1,
                      onTap: () =>
                          setState(() => _questionDifficulty = difficulty.$1),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (!_isEditing && _consentTerms.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ConsentSection(
                      terms: _consentTerms,
                      agreed: _consentAgreed,
                      errorText: _consentError,
                      onChanged: (termId, value) => setState(() {
                        _consentAgreed[termId] = value;
                        _acknowledgedDeclinedTermIds = const {};
                      }),
                      onAllChanged: (value) => setState(() {
                        for (final term in _consentTerms) {
                          _consentAgreed[term.termId] = value;
                        }
                        _acknowledgedDeclinedTermIds = const {};
                      }),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const ValueKey('submit-child-registration'),
                    label: _isEditing ? '저장하기' : '등록하기',
                    isLoading:
                        widget.controller.registrationStatus ==
                        ChildRegistrationStatus.submitting,
                    onPressed: _submit,
                  ),
                  if (_isEditing) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      key: const ValueKey('delete-child-profile'),
                      label: '아이 프로필 삭제',
                      variant: AppButtonVariant.danger,
                      onPressed: _delete,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 아동 데이터 사용 동의 섹션.
///
/// 서버가 발행한 약관을 그대로 보여주고 필수/선택 표시도 서버 값을 따른다. 기본값은
/// 전부 미동의이며, 사용자가 켜지 않은 항목은 동의로 기록되지 않는다(가드레일 9절).
class _ConsentSection extends StatelessWidget {
  const _ConsentSection({
    required this.terms,
    required this.agreed,
    required this.errorText,
    required this.onChanged,
    required this.onAllChanged,
  });

  final List<ConsentTermDto> terms;
  final Map<int, bool> agreed;
  final String? errorText;
  final void Function(int termId, bool value) onChanged;
  final ValueChanged<bool> onAllChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '아이 데이터 사용 동의',
        style: TextStyle(
          color: AppColors.inkMuted,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      const Text(
        '음성으로 답하기는 음성 처리 동의가 있어야 사용할 수 있어요. '
        '동의하지 않으면 아이는 선택형 답변으로 대화해요.',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
      ),
      CheckboxListTile(
        key: const ValueKey('child-consent-all'),
        value: terms.every((term) => agreed[term.termId] ?? false),
        onChanged: (value) => onAllChanged(value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: const Text(
          '전체 동의',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: const Text('필수 및 선택 약관에 모두 동의해요.'),
      ),
      const Divider(height: 1),
      for (final term in terms)
        CheckboxListTile(
          key: ValueKey('child-consent-${term.termCode}'),
          value: agreed[term.termId] ?? false,
          onChanged: (value) => onChanged(term.termId, value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            term.required ? '[필수] ${term.title}' : '[선택] ${term.title}',
            style: const TextStyle(color: AppColors.ink, fontSize: 15),
          ),
        ),
      if (errorText != null)
        Text(
          errorText!,
          key: const ValueKey('child-consent-error'),
          style: const TextStyle(
            color: AppColors.error,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
    ],
  );
}

class _CharacterSelector extends StatelessWidget {
  const _CharacterSelector({
    required this.characters,
    required this.selected,
    required this.onSelected,
  });

  final List<(String, String)> characters;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text(
        '아이와 함께할 친구를 골라주세요',
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.md,
        children: [
          for (final character in characters)
            Semantics(
              button: true,
              selected: selected == character.$1,
              child: InkWell(
                key: ValueKey('character-${character.$1}'),
                onTap: () => onSelected(character.$1),
                borderRadius: BorderRadius.circular(40),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 66,
                  height: 66,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceSoft,
                    border: Border.all(
                      color: selected == character.$1
                          ? AppColors.leaf
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Text(
                    character.$2,
                    style: const TextStyle(fontSize: 34),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

class _BirthDateField extends StatelessWidget {
  const _BirthDateField({
    required this.value,
    required this.errorText,
    required this.onTap,
  });

  final DateTime? value;
  final String? errorText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const ValueKey('child-birth-date'),
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.md),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: '생년월일 *',
        errorText: errorText,
        suffixIcon: const Icon(Icons.calendar_month_rounded),
      ),
      child: Text(
        value == null
            ? '생년월일을 선택해 주세요'
            : '${value!.year}년 ${value!.month}월 ${value!.day}일',
        style: TextStyle(
          color: value == null ? AppColors.inkMuted : AppColors.ink,
          fontSize: 16,
        ),
      ),
    ),
  );
}
