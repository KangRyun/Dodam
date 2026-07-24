import 'package:flutter/material.dart';

import '../../../../app/state/guardian_child_controller.dart';
import '../../../../design_system/design_system.dart';
import '../../data/dto/child_dtos.dart';

class ChildRegistrationScreen extends StatefulWidget {
  const ChildRegistrationScreen({required this.controller, super.key});

  final GuardianChildController controller;

  @override
  State<ChildRegistrationScreen> createState() =>
      _ChildRegistrationScreenState();
}

class _ChildRegistrationScreenState extends State<ChildRegistrationScreen> {
  final _nicknameController = TextEditingController();
  DateTime? _birthDate;
  String _relationshipType = 'MOTHER';
  String _preferredCharacter = 'BEAR';
  String _questionDifficulty = 'PRESCHOOL';
  bool _submitted = false;

  static const _characters = [
    ('RABBIT', '🐰'),
    ('GIRL', '👧'),
    ('BEAR', '🐻'),
    ('FOX', '🦊'),
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
    widget.controller.resetRegistration();
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
    if (_nicknameError != null || _birthDateError != null) return;

    final birthDate = _birthDate!;
    final succeeded = await widget.controller.registerChild(
      CreateChildRequestDto(
        nickname: _nicknameController.text.trim(),
        birthDate:
            '${birthDate.year.toString().padLeft(4, '0')}-'
            '${birthDate.month.toString().padLeft(2, '0')}-'
            '${birthDate.day.toString().padLeft(2, '0')}',
        relationshipType: _relationshipType,
        preferredCharacter: _preferredCharacter,
        questionDifficulty: _questionDifficulty,
        responseModes: const ['VOICE'],
      ),
    );
    if (!mounted) return;
    if (succeeded) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('아이 등록에 실패했어요. 잠시 후 다시 시도해 주세요.')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '아이 등록',
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
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const ValueKey('submit-child-registration'),
                    label: '등록하기',
                    isLoading:
                        widget.controller.registrationStatus ==
                        ChildRegistrationStatus.submitting,
                    onPressed: _submit,
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
