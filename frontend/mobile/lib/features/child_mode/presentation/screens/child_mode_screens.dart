import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/app_router.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../design_system/design_system.dart';
import '../../../activity/presentation/screens/activity_screens.dart';
import '../../../child/data/dto/child_dtos.dart';
import '../../../drawing/application/drawing_session_start_controller.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';
import '../../../drawing/domain/repositories/drawing_repository.dart';
import '../../../drawing/presentation/screens/input_method_select_screen.dart';
import '../../data/costume_preference_store.dart';
import '../../data/child_home_intro_store.dart';
import '../../domain/dodam_costume.dart';
import '../widgets/activity_guide_dialog.dart';

/// 아동 홈 "놀이 언덕" 배경 장면 색(S15P11B209-750). 이 화면 전용이라 공용
/// 토큰 대신 여기 둔다.
const Color _skyTop = Color(0xFFBFE3F0);
const Color _skyLow = Color(0xFFEAF6EF);
const Color _grass = Color(0xFFA7D585);
const Color _grassDeep = Color(0xFF8AC468);
const Color _treeTrunk = Color(0xFFC79A66);

enum _ActivityLoadStatus { loading, loaded, empty, error }

enum _DrawingStartChoice { resume, startNew }

enum _CharacterIntroChoice { useCurrent, pick, dismissed }

enum _CharacterGuideStatus { inactive, choosing, saving, failure }

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

String _createIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

String _htpSubjectTitle(String? subject) => htpSubjectTitle(subject);

String _nextHtpSubjectTitle(String? currentSubject) => switch (currentSubject) {
  'HOUSE' => '나무 그리기',
  'TREE' => '사람 그리기',
  _ => 'HTP 그림',
};

/// HOUSE·TREE 대화가 끝나 세션이 REFLECTION에 머문 상태인지.
///
/// 이 상태는 `steps/next`를 아직 부르지 않았다는 뜻이므로, 재진입 시
/// Canvas나 끝난 대화가 아니라 다음 주제 입력 방식 선택으로 복원해야 한다.
bool _isAwaitingNextHtpSubject(DrawingSessionResolution resolution) {
  final activity = resolution.activityContext;
  if (!activity.isHtp || resolution.currentStage != 'REFLECTION') return false;
  return activity.drawingSubject == 'HOUSE' ||
      activity.drawingSubject == 'TREE';
}

/// PERSON `steps/next`까지 끝나 세션이 COMPLETED가 된 상태인지.
///
/// Reflection과 주제 전환이 모두 끝났다는 뜻이므로 남은 일은 Assessment
/// Complete뿐이다. 다른 HTP COMPLETED와 섞이지 않도록 주제가 PERSON인지도
/// 함께 확인한다.
bool _isHtpPersonCompletedSession(DrawingSessionResolution resolution) {
  final activity = resolution.activityContext;
  return activity.isHtp &&
      activity.drawingSubject == 'PERSON' &&
      resolution.currentStage == 'COMPLETED';
}

/// Backend가 `complete` 재호출을 허용하는 상태인지.
///
/// 서비스는 `IN_PROGRESS`·`FAILED`에서만 완료를 접수하고, 이미 `ANALYZING`·
/// `COMPLETED`면 새 Idempotency-Key에 충돌 오류를 던진다. 앱을 다시 켜면
/// 원래 Key를 알 수 없으므로 이 상태 판정으로만 호출 여부를 정한다.
bool _htpCompletionCallable(String? htpStatus) =>
    htpStatus == 'IN_PROGRESS' || htpStatus == 'FAILED';

class ChildModeHomeScreen extends StatefulWidget {
  const ChildModeHomeScreen({
    required this.child,
    required this.drawingRepository,
    this.completionSnapshotProvider,
    this.htpPhotoUploadEnabled = false,
    this.costumeStore,
    this.introStore,
    this.availableCostumes = DodamCostume.values,
    this.onCharacterSelected,
    this.preparedResolution,
    this.autoStartPrepared = false,
    super.key,
  });

  final ChildSummaryDto child;
  final DrawingRepository drawingRepository;
  final Future<BinaryUploadDto?> Function()? completionSnapshotProvider;

  /// HTP 사진으로 시작하기 옵션 노출 여부(S15P11B209-702, 기본 꺼짐).
  final bool htpPhotoUploadEnabled;

  /// 도담이 코스튬 로컬 저장소. 주입하지 않으면 기기 보안 저장소를 쓴다.
  final CostumePreferenceStore? costumeStore;
  final ChildHomeIntroStore? introStore;

  /// 홈 캐러셀에서 선택할 수 있는 친구 목록. production은 전체 목록을 사용하며,
  /// 빈 목록이나 단일 목록도 안전하게 표시할 수 있다.
  final List<DodamCostume> availableCostumes;

  /// 아동이 캐릭터를 고르면 그 아이의 `preferredCharacter`로 저장하도록 알린다
  /// (S15P11B209-505). 프로필 이미지가 이 값에서 그려진다. 주입하지 않으면
  /// 로컬 코스튬 저장까지만 하고 프로필에는 반영되지 않는다.
  final Future<bool> Function(int childId, String characterCode)?
  onCharacterSelected;

  /// 보호자가 활동 주제와 입력 방식을 선택해 미리 준비한 새 활동.
  final DrawingSessionResolution? preparedResolution;

  /// 참이면 아동 홈을 거치지 않고 준비된 활동(이어 그리기)을 바로 캔버스로 연다.
  final bool autoStartPrepared;

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

  /// 화면 진입 시 진행 중 활동을 한 번만 확인해 팝업 중복 생성을 막는다.
  bool _checkingActiveSession = false;
  bool _entryResolved = false;
  bool _replaceActiveOnSelection = false;
  DrawingSessionResolution? _preparedResolution;

  late final CostumePreferenceStore _costumeStore;
  late final ChildHomeIntroStore _introStore;
  late final PageController _costumeController;
  late DodamCostume _costume;
  late DodamCostume _confirmedCostume;
  final FocusNode _costumeFocusNode = FocusNode(debugLabel: 'costume-selector');
  final GlobalKey _costumeKey = GlobalKey();

  /// 캐릭터 선택을 백엔드에 저장하기 전 잠깐 모으는 디바운스(S15P11B209-505).
  /// 스와이프마다 저장하지 않고, 잠시 멈춘 뒤 마지막 선택만 한 번 저장한다.
  Timer? _persistCharacterTimer;
  String? _pendingCharacterCode;
  int _characterSaveGeneration = 0;
  int _costumeLoadGeneration = 0;
  bool _characterSaveInFlight = false;
  bool _introCheckRunning = false;
  bool _introOpen = false;
  bool _introHandled = false;
  bool _introAllowedForResolvedEntry = false;
  _CharacterGuideStatus _characterGuideStatus = _CharacterGuideStatus.inactive;
  int? _characterGuideChildId;
  bool _characterGuideInteracted = false;
  int _costumeSelectionGeneration = 0;
  static const Duration _persistCharacterDelay = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _costumeStore = widget.costumeStore ?? CostumePreferenceStore();
    _introStore = widget.introStore ?? SecureChildHomeIntroStore();
    _costume = _costumeFromCode(widget.child.preferredCharacter);
    _confirmedCostume = _costume;
    _costumeController = PageController(initialPage: _costumeIndex(_costume));
    _preparedResolution = widget.preparedResolution;
    // 자동 시작(이어 그리기)은 홈을 "확인 중" 상태로 두고 곧바로 캔버스를 연다.
    _entryResolved = _preparedResolution != null && !widget.autoStartPrepared;
    unawaited(_loadCostume());
    unawaited(_loadDrawingTypes());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.autoStartPrepared && _preparedResolution != null) {
        unawaited(_autoStartPreparedResolution());
      } else if (_preparedResolution == null) {
        unawaited(_resolveEntry());
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChildModeHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child.childId == widget.child.childId) return;

    _persistCharacterTimer?.cancel();
    _persistCharacterTimer = null;
    _pendingCharacterCode = null;
    _characterSaveInFlight = false;
    _characterSaveGeneration++;
    _costumeLoadGeneration++;
    _introCheckRunning = false;
    _introOpen = false;
    _introHandled = false;
    _introAllowedForResolvedEntry = false;
    _characterGuideStatus = _CharacterGuideStatus.inactive;
    _characterGuideChildId = null;
    _characterGuideInteracted = false;
    _costumeSelectionGeneration++;

    final costume = _costumeFromCode(widget.child.preferredCharacter);
    _costume = costume;
    _confirmedCostume = costume;
    _jumpToCostume(costume);
    unawaited(_loadCostume());
  }

  /// 보호자가 정해 넘긴 활동을 홈을 거치지 않고 바로 연다.
  ///
  /// 사진 업로드·완료까지 끝난 세션(`UPLOAD`+`CONVERSING`)만 이 경로로 들어온다
  /// (S15P11B209-834). 캔버스 최초 선택은 기존처럼 아이가 홈에서 시작한다.
  /// 어떤 화면을 열지는 [_openResolution]이 판정한다.
  Future<void> _autoStartPreparedResolution() async {
    final resolution = _preparedResolution;
    if (resolution == null) return;
    setState(() => _preparedResolution = null);
    // Draft 복원 의사만 전달한다. `UPLOAD` 세션 제외는 [_openResolution]이 한다.
    await _openResolution(resolution, autoRestoreDraft: true);
    if (!mounted) return;
    // 캔버스에서 뒤로 나온 경우 _openResolution 이 _resolveEntry 를 다시 예약한다.
    // 그 밖의 경로(감정·완료 화면 등)에서는 홈을 상호작용 가능한 상태로 되돌린다.
    if (!_entryResolved && !_checkingActiveSession) {
      setState(() => _entryResolved = true);
    }
  }

  @override
  void dispose() {
    // 아직 저장 안 된 마지막 선택이 있으면 나가기 전에 보낸다.
    if (_persistCharacterTimer?.isActive ?? false) _flushPersistCharacter();
    _persistCharacterTimer?.cancel();
    _costumeController.dispose();
    _costumeFocusNode.dispose();
    super.dispose();
  }

  /// 지원 그림 유형 중 기본 그림 활동 진입에 사용하는 그림일기.
  DrawingTypeDto? get _artDiaryType {
    for (final type in _drawingTypes) {
      if (type.code == 'ART_DIARY') return type;
    }
    return null;
  }

  Future<void> _openPreparedActivity() async {
    final resolution = _preparedResolution;
    if (resolution == null) return;
    setState(() => _preparedResolution = null);
    await _openResolution(resolution, startFresh: true);
    if (!mounted) return;
    setState(() => _entryResolved = false);
    unawaited(_resolveEntry());
  }

  /// 저장된 캐릭터로 캐러셀 첫 페이지를 맞춘다. 프로필과 같은 값을 쓰도록
  /// 아이의 `preferredCharacter`를 우선하고, 없으면 로컬 코스튬으로 되돌린다
  /// (S15P11B209-505).
  Future<void> _loadCostume() async {
    final generation = ++_costumeLoadGeneration;
    final childId = widget.child.childId;
    final preferred = widget.child.preferredCharacter;
    final code = preferred ?? await _costumeStore.read(childId);
    if (!mounted ||
        generation != _costumeLoadGeneration ||
        childId != widget.child.childId) {
      return;
    }
    final costume = _costumeFromCode(code);
    _confirmedCostume = costume;
    if (costume != _costume) setState(() => _costume = costume);
    _jumpToCostume(costume);
  }

  DodamCostume _costumeFromCode(String? code) {
    final costumes = widget.availableCostumes;
    if (costumes.isEmpty) return DodamCostume.base;
    return costumes.firstWhere(
      (costume) => costume.code == code,
      orElse: () => costumes.first,
    );
  }

  int _costumeIndex(DodamCostume costume) {
    final index = widget.availableCostumes.indexOf(costume);
    return index < 0 ? 0 : index;
  }

  void _jumpToCostume(DodamCostume costume) {
    if (widget.availableCostumes.isEmpty) return;
    final index = _costumeIndex(costume);
    void jump() {
      if (!mounted || !_costumeController.hasClients) return;
      _costumeController.jumpToPage(index);
    }

    if (_costumeController.hasClients) {
      jump();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    }
  }

  /// 캐러셀에서 캐릭터가 바뀌면 상태·로컬 저장을 즉시 반영하고, 프로필에 반영할
  /// `preferredCharacter` 저장은 디바운스로 마지막 선택만 보낸다(S15P11B209-505).
  void _onCostumeSelected(int index) {
    final costumes = widget.availableCostumes;
    if (index < 0 || index >= costumes.length) return;
    final costume = costumes[index];
    if (costume == _costume) return;
    HapticFeedback.selectionClick();
    _costumeSelectionGeneration++;
    setState(() {
      _costume = costume;
      if (_characterGuideStatus != _CharacterGuideStatus.inactive &&
          _characterGuideChildId == widget.child.childId) {
        _characterGuideInteracted = true;
        _characterGuideStatus = _CharacterGuideStatus.choosing;
      }
    });
    unawaited(_costumeStore.write(widget.child.childId, costume.code));
    _schedulePersistCharacter(costume.code);
  }

  void _schedulePersistCharacter(String code) {
    if (!_characterSaveInFlight && code == _confirmedCostume.code) {
      _persistCharacterTimer?.cancel();
      _persistCharacterTimer = null;
      _pendingCharacterCode = null;
      return;
    }
    if (_pendingCharacterCode == code &&
        (_persistCharacterTimer?.isActive ?? false)) {
      return;
    }
    _pendingCharacterCode = code;
    _persistCharacterTimer?.cancel();
    _persistCharacterTimer = Timer(
      _persistCharacterDelay,
      _flushPersistCharacter,
    );
  }

  void _flushPersistCharacter() {
    _persistCharacterTimer?.cancel();
    _persistCharacterTimer = null;
    if (_characterSaveInFlight) return;
    final code = _pendingCharacterCode;
    _pendingCharacterCode = null;
    if (code == null || code == _confirmedCostume.code) return;
    unawaited(_persistCharacter(code));
  }

  Future<void> _persistCharacter(String code) async {
    if (_characterSaveInFlight) {
      _pendingCharacterCode = code;
      return;
    }
    _characterSaveInFlight = true;
    final generation = ++_characterSaveGeneration;
    final selectionGeneration = _costumeSelectionGeneration;
    final childId = widget.child.childId;
    final requested = _costumeFromCode(code);
    final guideRequest =
        _characterGuideStatus != _CharacterGuideStatus.inactive &&
        _characterGuideChildId == childId &&
        _characterGuideInteracted;
    if (guideRequest && mounted) {
      setState(() => _characterGuideStatus = _CharacterGuideStatus.saving);
    }
    final succeeded =
        await widget.onCharacterSelected?.call(childId, code) ?? true;
    if (!mounted ||
        generation != _characterSaveGeneration ||
        childId != widget.child.childId) {
      return;
    }
    _characterSaveInFlight = false;
    final queuedCode = _pendingCharacterCode;
    _pendingCharacterCode = null;
    if (succeeded) {
      _confirmedCostume = requested;
      if (guideRequest &&
          queuedCode == null &&
          selectionGeneration == _costumeSelectionGeneration &&
          requested == _costume &&
          _isCurrentHomeRoute) {
        await _completeCharacterGuide(
          childId: childId,
          saveGeneration: generation,
          selectionGeneration: selectionGeneration,
        );
      }
    } else if (queuedCode == null || queuedCode == requested.code) {
      setState(() {
        _costume = _confirmedCostume;
        if (guideRequest) {
          _characterGuideStatus = _CharacterGuideStatus.failure;
        }
      });
      unawaited(
        _costumeStore.write(widget.child.childId, _confirmedCostume.code),
      );
      _jumpToCostume(_confirmedCostume);
      showAppMessage(
        context,
        message: guideRequest
            ? '친구를 정하지 못했어요. 다시 골라볼까요?'
            : '친구를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.',
        type: AppMessageType.error,
      );
    }

    if (queuedCode != null &&
        queuedCode != requested.code &&
        queuedCode != _confirmedCostume.code) {
      unawaited(_persistCharacter(queuedCode));
    }
  }

  bool get _isCurrentHomeRoute =>
      mounted && (ModalRoute.of(context)?.isCurrent ?? false);

  Future<void> _completeCharacterGuide({
    required int childId,
    required int saveGeneration,
    required int selectionGeneration,
  }) async {
    if (!_isCurrentHomeRoute ||
        childId != widget.child.childId ||
        _characterGuideChildId != childId ||
        !_characterGuideInteracted ||
        saveGeneration != _characterSaveGeneration ||
        selectionGeneration != _costumeSelectionGeneration) {
      return;
    }

    setState(() {
      _characterGuideStatus = _CharacterGuideStatus.inactive;
      _characterGuideChildId = null;
      _characterGuideInteracted = false;
    });
    showAppMessage(
      context,
      message: '새 친구와 함께 시작해 볼까?',
      type: AppMessageType.success,
    );
    try {
      await _introStore.markSeen(childId);
    } on Object {
      // 캐릭터 저장은 끝났다. 안내 상태 저장 실패로 홈 사용을 막지 않고,
      // 다음 정상 진입에서 안내를 다시 보여 줄 수 있게 둔다.
    }
  }

  void _startCharacterGuide(int childId) {
    if (!mounted || childId != widget.child.childId) return;
    setState(() {
      _characterGuideStatus = _CharacterGuideStatus.choosing;
      _characterGuideChildId = childId;
      _characterGuideInteracted = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _characterGuideStatus == _CharacterGuideStatus.inactive ||
          _characterGuideChildId != widget.child.childId) {
        return;
      }
      _costumeFocusNode.requestFocus();
      final selectorContext = _costumeKey.currentContext;
      if (selectorContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            selectorContext,
            duration: const Duration(milliseconds: 240),
            alignment: 0.35,
          ),
        );
      }
    });
  }

  void _dismissCharacterGuide() {
    if (_characterGuideStatus == _CharacterGuideStatus.inactive) return;
    setState(() {
      _characterGuideStatus = _CharacterGuideStatus.inactive;
      _characterGuideChildId = null;
      _characterGuideInteracted = false;
    });
  }

  Future<void> _markCurrentCharacterIntroSeen(int childId) async {
    try {
      await _introStore.markSeen(childId);
    } on Object {
      // 명시적으로 현재 친구를 선택한 흐름은 막지 않는다. 저장 실패 시 다음
      // 진입에서 안내가 다시 나타날 수 있다.
    }
  }

  void _stepCostume(int delta) {
    final costumes = widget.availableCostumes;
    final count = costumes.length;
    if (count <= 1) return;
    final current = costumes.indexOf(_costume);
    final safeCurrent = current < 0 ? 0 : current;
    final next = (safeCurrent + delta) % count;
    _onCostumeSelected(next);
    if (_costumeController.hasClients) {
      _costumeController.jumpToPage(next);
    }
  }

  Future<void> _resolveEntry() async {
    if (_checkingActiveSession || _entryResolved) return;
    setState(() {
      _checkingActiveSession = true;
      _introAllowedForResolvedEntry = false;
    });
    try {
      final controller = DrawingSessionStartController(
        repository: widget.drawingRepository,
      );
      final activeSession = await controller.findActiveSession(
        childId: widget.child.childId,
      );
      if (!mounted) return;
      if (activeSession == null) {
        setState(() {
          _entryResolved = true;
          _introAllowedForResolvedEntry = true;
        });
        unawaited(_maybeShowCharacterIntro());
        return;
      }

      // 홈 위에 다른 화면(그림 전시관 등)이 올라와 있으면 "이어 그리기" 팝업을 그
      // 화면 위에 띄우지 않는다. _entryResolved 를 확정하지 않으므로 홈으로 돌아오면
      // (_openPastDrawings 복귀 처리에서) 다시 확인해 그때 띄운다.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }

      // 팝업 뒤 화면은 정적인 활동 목록으로 유지해 불필요한 로딩 애니메이션을
      // 계속 실행하지 않는다. 팝업이 입력을 막으므로 활동 중복 시작은 발생하지 않는다.
      setState(() => _entryResolved = true);
      final choice = await _showDrawingStartDialog();
      if (!mounted) return;
      if (choice == _DrawingStartChoice.startNew) {
        setState(() {
          _replaceActiveOnSelection = true;
          _entryResolved = true;
          _introAllowedForResolvedEntry = true;
        });
        return;
      }
      if (choice == _DrawingStartChoice.resume) {
        await _openResolution(
          controller.resume(activeSession),
          autoRestoreDraft: true,
        );
      }
    } on Object {
      if (mounted) {
        showAppMessage(
          context,
          message: '진행 중인 활동을 확인하지 못했어요. 다시 시도해 주세요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _checkingActiveSession = false);
        unawaited(_maybeShowCharacterIntro());
      }
    }
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
      unawaited(_maybeShowCharacterIntro());
    } on Object {
      if (mounted) setState(() => _status = _ActivityLoadStatus.error);
    }
  }

  Future<void> _maybeShowCharacterIntro() async {
    if (_introHandled ||
        _introCheckRunning ||
        _introOpen ||
        _status != _ActivityLoadStatus.loaded ||
        !_entryResolved ||
        !_introAllowedForResolvedEntry ||
        _checkingActiveSession ||
        _preparedResolution != null ||
        _startingDrawingTypeId != null ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    _introCheckRunning = true;
    final childId = widget.child.childId;
    final seen = await _introStore.hasSeen(childId);
    if (!mounted || childId != widget.child.childId) return;
    _introCheckRunning = false;
    if (seen) {
      _introHandled = true;
      return;
    }
    if (_introOpen ||
        _status != _ActivityLoadStatus.loaded ||
        !_entryResolved ||
        !_introAllowedForResolvedEntry ||
        _checkingActiveSession ||
        _preparedResolution != null ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    _introOpen = true;
    final choice = await _showCharacterIntro(childId);
    if (!mounted || childId != widget.child.childId) return;
    _introOpen = false;
    _introHandled = true;
    switch (choice) {
      case _CharacterIntroChoice.pick:
        _startCharacterGuide(childId);
      case _CharacterIntroChoice.useCurrent:
        await _markCurrentCharacterIntroSeen(childId);
      case _CharacterIntroChoice.dismissed || null:
        break;
    }
  }

  Future<_CharacterIntroChoice?> _showCharacterIntro(int childId) {
    var closing = false;
    return showDialog<_CharacterIntroChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        void close(_CharacterIntroChoice choice) {
          if (closing) return;
          closing = true;
          Navigator.of(dialogContext).pop(choice);
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) close(_CharacterIntroChoice.dismissed);
          },
          child: Dialog(
            key: const ValueKey('child-character-intro-dialog'),
            insetPadding: const EdgeInsets.all(AppSpacing.md),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: AppColors.sunshine, width: 2),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: Image.asset(
                          'assets/characters/dodam_intro.png',
                          key: const ValueKey('child-character-intro-mascot'),
                          height: 116,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Semantics(
                        header: true,
                        child: const Text(
                          '반가워!\n함께할 도담이를 골라볼까?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        '그림을 그릴 때 옆에서 함께할 친구야.\n'
                        '지금 고르지 않아도 나중에 언제든 바꿀 수 있어!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            key: const ValueKey('pick-character-from-intro'),
                            onPressed: () => close(_CharacterIntroChoice.pick),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.leaf,
                            ),
                            child: const Text('친구 골라보기'),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            key: const ValueKey('choose-character-later'),
                            onPressed: () =>
                                close(_CharacterIntroChoice.useCurrent),
                            child: const Text('지금 도담이로 시작할래'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<_DrawingStartChoice?> _showDrawingStartDialog() {
    return showDialog<_DrawingStartChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
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
      ),
    );
  }

  Future<void> _selectActivity(DrawingTypeDto type) async {
    if (_startingDrawingTypeId != null || !_entryResolved) return;
    setState(() {
      _startingDrawingTypeId = type.drawingTypeId;
    });
    try {
      final controller = DrawingSessionStartController(
        repository: widget.drawingRepository,
      );
      final (icon, accentColor) = _visualForDrawingType(type.code);
      final resolution =
          await showActivityGuideDialog<DrawingSessionResolution?>(
            context: context,
            title: type.name,
            description: _descriptionForDrawingType(type),
            icon: icon,
            accentColor: accentColor,
            onStart: () => _startGuidedActivity(
              controller: controller,
              type: type,
              icon: icon,
              accentColor: accentColor,
              replaceActive: _replaceActiveOnSelection,
            ),
          );
      if (resolution == null || !mounted) return;
      await _openResolution(resolution, startFresh: true);
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

  Future<DrawingSessionResolution?> _startGuidedActivity({
    required DrawingSessionStartController controller,
    required DrawingTypeDto type,
    required IconData icon,
    required Color accentColor,
    required bool replaceActive,
  }) {
    if (type.code != 'HTP') {
      return _createSelectedActivity(
        controller: controller,
        type: type,
        replaceActive: replaceActive,
      );
    }
    return Navigator.of(context).push<DrawingSessionResolution>(
      MaterialPageRoute(
        builder: (_) => InputMethodSelectScreen(
          childId: widget.child.childId,
          drawingTypeId: type.drawingTypeId,
          title: type.name,
          description: _descriptionForDrawingType(type),
          icon: icon,
          accentColor: accentColor,
          repository: widget.drawingRepository,
          replaceActive: replaceActive,
          htpPhotoUploadEnabled: widget.htpPhotoUploadEnabled,
        ),
      ),
    );
  }

  Future<void> _openResolution(
    DrawingSessionResolution resolution, {
    bool autoRestoreDraft = false,
    bool startFresh = false,
  }) async {
    if (_isHtpPersonCompletedSession(resolution)) {
      // PERSON steps/next는 이미 성공해 세션이 COMPLETED다. Reflection도
      // steps/next도 다시 부르지 않고, 남은 Assessment Complete만 복구한다.
      await _recoverHtpAssessmentCompletion(resolution);
      return;
    }
    if (!resolution.activityContext.isHtp &&
        resolution.currentStage == 'REFLECTION') {
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
          inputMethod: resolution.inputMethod,
        ),
      );
      return;
    }
    if (resolution.target == DrawingResolutionTarget.photoInput) {
      if (resolution.activityContext.isHtp && !widget.htpPhotoUploadEnabled) {
        showAppMessage(
          context,
          message: '사진으로 시작한 활동은 지금 이어갈 수 없어요. 보호자와 함께 다시 시도해 주세요.',
          type: AppMessageType.warning,
        );
        return;
      }
      // 사진을 아직 찍지 않은 UPLOAD 세션 — Canvas로 열지 않고 사진 촬영
      // 단계를 그대로 복원한다. 새 세션·새 HTP 활동을 만들지 않는다.
      await _restoreUploadInput(resolution);
      return;
    }
    if (_isAwaitingNextHtpSubject(resolution)) {
      // Conversation End가 세션을 REFLECTION으로 올린 뒤 아직 steps/next를
      // 부르지 않은 상태 — 감정 화면도 Canvas도 아니라 다음 주제 입력 방식
      // 선택으로 복원한다. 사용자가 고르기 전에는 steps/next가 나가지 않는다.
      await _restoreNextHtpSubjectInputMethod(resolution);
      return;
    }
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
          inputMethod: resolution.inputMethod,
        ),
      );
      return;
    }
    final route = AppNavigation.pushNamed<DrawingRouteResult>(
      context,
      AppRoutes.drawing(widget.child.childId.toString()),
      arguments: DrawingRouteArguments(
        sessionId: resolution.sessionId,
        repository: widget.drawingRepository,
        completionSnapshotProvider: widget.completionSnapshotProvider,
        resumeConversation: !resolution.isDrawingStage,
        // `UPLOAD` 세션에는 Canvas Draft가 없다. 조회·복원을 시도하지 않는다
        // (S15P11B209-834). `CANVAS`는 대화·회고 단계에서도 기존 복원 계약을
        // 그대로 유지한다.
        autoRestoreDraft: autoRestoreDraft && !resolution.isUploadInput,
        startFresh: startFresh,
        activityContext: resolution.activityContext,
        inputMethod: resolution.inputMethod,
      ),
    );
    if (route == null) return;
    final result = await route;
    if (!mounted || result == null) return;

    // HTP 주제 전환은 캔버스가 직접 라우팅하지 않고 다음 세션만 올려보낸다.
    // 어떤 화면을 열지는 이 함수 하나가 판정하므로, 사진으로 시작한 활동도
    // 나무·사람에서 다시 사진 입력 화면으로 들어간다(S15P11B209-834).
    if (result.nextResolution case final next?) {
      await _openResolution(next, startFresh: true);
      return;
    }

    // 캔버스에서 뒤로 나온 경우에만 진행 중 세션을 다시 확인한다.
    // 완료·감정 화면으로 이동한 경우에는 기존 라우팅 흐름을 유지한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _entryResolved = false;
        _checkingActiveSession = false;
      });
      unawaited(_resolveEntry());
    });
  }

  /// 이미 만든 UPLOAD 세션을 복원해 사진 촬영 단계로 바로 들어간다.
  ///
  /// 화면 생성은 라우터 한 곳에만 두어(S15P11B209-834) 캔버스에서 주제를 넘길
  /// 때도 같은 인자·같은 화면을 쓰게 한다.
  Future<void> _restoreUploadInput(DrawingSessionResolution resolution) async {
    final (icon, accentColor) = _visualForDrawingType(
      resolution.activityContext.isHtp ? 'HTP' : 'ART_DIARY',
    );
    final route = AppNavigation.pushNamed<DrawingSessionResolution>(
      context,
      AppRoutes.drawingInputMethod(widget.child.childId.toString()),
      arguments: InputMethodSelectRouteArguments(
        childId: widget.child.childId,
        drawingTypeId: 0,
        title: _htpSubjectTitle(resolution.activityContext.drawingSubject),
        description: '아까 찍던 사진을 마저 올려볼까?',
        icon: icon,
        accentColor: accentColor,
        repository: widget.drawingRepository,
        existingDrawingSessionId: resolution.sessionId,
        restoredActivityContext: resolution.activityContext,
      ),
    );
    if (route == null) return;
    final advanced = await route;
    if (advanced == null || !mounted) return;
    await _openResolution(advanced);
  }

  /// HOUSE·TREE REFLECTION 재진입 — 다음 주제 입력 방식 선택을 복원한다.
  Future<void> _restoreNextHtpSubjectInputMethod(
    DrawingSessionResolution resolution,
  ) async {
    final assessmentId = resolution.activityContext.htpAssessmentId;
    if (assessmentId == null) return;
    final (icon, accentColor) = _visualForDrawingType('HTP');
    final advanced = await Navigator.of(context).push<DrawingSessionResolution>(
      MaterialPageRoute(
        builder: (_) => InputMethodSelectScreen(
          childId: widget.child.childId,
          drawingTypeId: 0,
          title: _nextHtpSubjectTitle(
            resolution.activityContext.drawingSubject,
          ),
          description: '이번에는 어떻게 그릴까?',
          icon: icon,
          accentColor: accentColor,
          repository: widget.drawingRepository,
          htpAssessmentId: assessmentId,
          htpPhotoUploadEnabled: widget.htpPhotoUploadEnabled,
        ),
      ),
    );
    if (advanced == null || !mounted) return;
    await _openResolution(advanced, startFresh: true);
  }

  /// PERSON 완료 직후 앱이 종료된 경우 남은 Assessment Complete만 복구한다.
  ///
  /// Reflection과 `steps/next`는 이미 끝나 있으므로 다시 부르지 않고,
  /// `steps/next`용 새 Key도 만들지 않는다. 완료 호출은 서버가 접수 가능한
  /// 상태(`IN_PROGRESS`·`FAILED`)일 때만 보내고, 이미 `ANALYZING`·
  /// `COMPLETED`면 호출 없이 결과 화면으로 보낸다.
  Future<void> _recoverHtpAssessmentCompletion(
    DrawingSessionResolution resolution,
  ) async {
    final assessmentId = resolution.activityContext.htpAssessmentId;
    final repository = widget.drawingRepository;
    if (assessmentId != null &&
        repository is HtpDrawingRepository &&
        _htpCompletionCallable(resolution.activityContext.htpStatus)) {
      await (repository as HtpDrawingRepository).completeHtpAssessment(
        assessmentId,
        idempotencyKey: _createIdempotencyKey(),
      );
    }
    if (!mounted) return;
    await AppNavigation.pushNamed(
      context,
      AppRoutes.activityComplete(widget.child.childId.toString()),
      arguments: ActivityCompleteRouteArguments(
        sessionId: resolution.sessionId,
        repository: widget.drawingRepository,
      ),
    );
  }

  /// 오른쪽 "그림 그리기" 영역. 아동 홈에서는 그림일기로 바로 진입한다.
  Widget _buildDrawSection() {
    switch (_status) {
      case _ActivityLoadStatus.loading:
        return const AppLoadingView(
          message: '어떤 활동이 있는지 불러오고 있어요',
          childFriendly: true,
        );
      case _ActivityLoadStatus.error:
        return AppErrorView(
          title: '활동을 불러오지 못했어요',
          message: '잠시 후 다시 시도해 주세요.',
          onRetry: () => unawaited(_loadDrawingTypes()),
          childFriendly: true,
        );
      case _ActivityLoadStatus.empty:
        return const AppEmptyView(
          title: '아직 준비된 그림 활동이 없어요',
          message: '조금 있다가 다시 확인해 볼까?',
          childFriendly: true,
        );
      case _ActivityLoadStatus.loaded:
        if (!_entryResolved) {
          return const AppLoadingView(
            message: '그리던 활동이 있는지 확인하고 있어요',
            childFriendly: true,
          );
        }
        final artDiary = _artDiaryType;
        if (artDiary == null) {
          return const AppEmptyView(
            title: '아직 그림일기를 준비 중이에요',
            message: '조금 있다가 다시 확인해 볼까?',
            childFriendly: true,
          );
        }
        // 안내 팝업이 열린 동안 버튼 뒤에서 무한 로딩(스피너)을 돌리지 않는다.
        // 팝업이 입력을 막으므로 onTap만 비워 중복 시작을 방지한다.
        return _DrawEntryButton(
          key: const ValueKey('draw-entry'),
          onTap: _startingDrawingTypeId == null
              ? () => unawaited(
                  _preparedResolution == null
                      ? _selectActivity(artDiary)
                      : _openPreparedActivity(),
                )
              : null,
        );
    }
  }

  Widget _carousel() => _CharacterSelectionGuide(
    status: _characterGuideStatus,
    child: Focus(
      key: _costumeKey,
      focusNode: _costumeFocusNode,
      child: _CostumeCarousel(
        controller: _costumeController,
        costumes: widget.availableCostumes,
        selected: _costume,
        onSelected: _onCostumeSelected,
        onStep: _stepCostume,
      ),
    ),
  );

  /// 이젤 아래 secondary 입구. 활동 로딩 상태와 무관하게 항상 보여준다.
  Widget _pastDrawings() => _PastDrawingsButton(
    key: const ValueKey('past-drawings-entry'),
    onTap: () => unawaited(_openPastDrawings()),
  );

  /// 지난 그림 보기 — 아이의 "그림 전시관"으로 이동한다.
  ///
  /// 갤러리 화면(HISTORY-01 활동 기록 재사용)은 라우터가 `activityRepository`와
  /// 함께 조립한다. 홈은 childId만 넘긴다.
  Future<void> _openPastDrawings() async {
    await Navigator.of(
      context,
    ).pushNamed(AppRoutes.childGallery(widget.child.childId.toString()));
    // 전시관으로 넘어가느라 진입 확인(이어 그리기 여부)이 홈 위에서 미뤄졌다면,
    // 돌아온 지금 다시 확인해 필요하면 이어 그리기 팝업을 띄운다.
    if (!mounted) return;
    if (!_entryResolved && !_checkingActiveSession) {
      unawaited(_resolveEntry());
    }
  }

  Widget _title(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '${widget.child.nickname}, 오늘은 무엇을 그려 볼까?',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w900,
          shadows: const [
            Shadow(
              color: Color(0x40FFFFFF),
              blurRadius: 8,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      const Text(
        '친구를 고르고, 그림을 그려 볼까?',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.inkMuted,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  Widget _backButton(BuildContext context) => Semantics(
    button: true,
    label: '뒤로 가기',
    child: _Pressable(
      onTap: () => AppRouter.goProfileSelection(context),
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
            Icon(Icons.arrow_back_rounded, color: AppColors.inkMuted, size: 20),
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
  );

  Widget _guardianReturn(BuildContext context) => Tooltip(
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
  );

  /// 태블릿(넓은 화면): 캐릭터는 언덕 위에 서고 이젤은 오른쪽에 세운다.
  Widget _wideBody(BuildContext context) => Column(
    children: [
      _title(context),
      const SizedBox(height: AppSpacing.md),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _carousel(),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Align(
                // 하단 정렬 + 살짝 왼쪽으로 당겨 캐릭터와 균형을 맞추고
                // 오른쪽 나무와 겹치지 않게 한다.
                alignment: const Alignment(-0.6, 1),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  // 이젤(고정 높이)+지난 그림 카드가 짧은 화면에서 넘치지 않도록
                  // 필요할 때만 살짝 축소한다(큰 태블릿에선 원본 크기 유지).
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    // 이젤·지난 그림 카드는 둘 다 폭 300으로 고정돼 좌우 가장자리가 맞는다.
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDrawSection(),
                        // 이젤 다리(bottom -16)를 지나 secondary와 시각적 간격을 준다.
                        const SizedBox(height: 34),
                        _pastDrawings(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  /// 좁은 화면: 세로로 쌓고 스크롤한다(오버플로 방지).
  Widget _narrowBody(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSizes.wideContentMaxWidth,
        ),
        child: Column(
          children: [
            _title(context),
            const SizedBox(height: AppSpacing.xl),
            _carousel(),
            const SizedBox(height: AppSpacing.xl),
            _buildDrawSection(),
            const SizedBox(height: AppSpacing.xl),
            _pastDrawings(),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _dismissCharacterGuide();
    },
    child: Scaffold(
      backgroundColor: _skyLow,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _PlaygroundScene())),
          const Positioned.fill(child: _SceneDecor()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: _guardianReturn(context),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _backButton(context),
                      ),
                    ],
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth >= 720
                          ? _wideBody(context)
                          : _narrowBody(context),
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
}

/// 실제 캐러셀 위에만 표시하는 비차단 단계형 안내.
///
/// 테두리와 문구는 [IgnorePointer]라 PageView swipe와 좌우 화살표 hit target을
/// 그대로 유지한다. 고정 높이 안에 겹쳐 그려 좁은 화면·가로 화면의 레이아웃도
/// 바꾸지 않는다.
class _CharacterSelectionGuide extends StatelessWidget {
  const _CharacterSelectionGuide({required this.status, required this.child});

  final _CharacterGuideStatus status;
  final Widget child;

  String get _message => switch (status) {
    _CharacterGuideStatus.inactive => '',
    _CharacterGuideStatus.choosing => '화살표를 눌러 함께할 도담이를 골라봐!',
    _CharacterGuideStatus.saving => '친구를 정하고 있어요',
    _CharacterGuideStatus.failure => '친구를 정하지 못했어요. 다시 골라볼까요?',
  };

  Color get _accent => switch (status) {
    _CharacterGuideStatus.failure => AppColors.error,
    _ => AppColors.leaf,
  };

  @override
  Widget build(BuildContext context) {
    final active = status != _CharacterGuideStatus.inactive;
    return Stack(
      key: const ValueKey('child-character-guide-region'),
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              key: const ValueKey('child-character-guide-highlight'),
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: active ? Border.all(color: _accent, width: 3) : null,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.22),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
        if (active)
          Positioned(
            top: 4,
            left: 60,
            right: 60,
            child: Semantics(
              key: const ValueKey('child-character-guide'),
              container: true,
              liveRegion: true,
              label: _message,
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: _accent, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (status == _CharacterGuideStatus.saving) ...[
                          SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: _accent,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Flexible(
                          child: Text(
                            _message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: status == _CharacterGuideStatus.failure
                                  ? AppColors.error
                                  : AppColors.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 왼쪽 도담이 코스튬 캐러셀(S15P11B209-750).
///
/// 옆으로 넘기거나(스와이프) 좌우 화살표로 코스튬을 바꾼다. 큰 캐릭터가 화면의
/// 주인공이 되도록 부드러운 받침 위에 올린다.
class _CostumeCarousel extends StatelessWidget {
  const _CostumeCarousel({
    required this.controller,
    required this.costumes,
    required this.selected,
    required this.onSelected,
    required this.onStep,
  });

  final PageController controller;
  final List<DodamCostume> costumes;
  final DodamCostume selected;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    if (costumes.isEmpty) {
      return Semantics(
        label: '선택할 친구가 없어요',
        child: const SizedBox(height: 320),
      );
    }
    final index = costumes.indexOf(selected);
    return Semantics(
      key: const ValueKey('costume-selection-semantics'),
      container: true,
      selected: true,
      label: '캐릭터 고르기',
      value: '${selected.label}, 선택됨',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 배경 장면(언덕) 위에 캐릭터가 그대로 서 있도록 카드 없이 투명하게 둔다.
          SizedBox(
            height: 320,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PageView.builder(
                  key: const ValueKey('costume-carousel'),
                  controller: controller,
                  onPageChanged: onSelected,
                  itemCount: costumes.length,
                  itemBuilder: (context, i) => _CostumeStage(
                    key: ValueKey('costume-stage-${costumes[i].code}'),
                    costume: costumes[i],
                  ),
                ),
                Positioned(
                  left: 0,
                  child: _CostumeChevron(
                    key: const ValueKey('costume-prev'),
                    icon: Icons.chevron_left_rounded,
                    semanticLabel: '이전 친구',
                    onTap: () => onStep(-1),
                  ),
                ),
                Positioned(
                  right: 0,
                  child: _CostumeChevron(
                    key: const ValueKey('costume-next'),
                    icon: Icons.chevron_right_rounded,
                    semanticLabel: '다음 친구',
                    onTap: () => onStep(1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              selected.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < costumes.length; i++)
                AnimatedContainer(
                  key: ValueKey('costume-indicator-${costumes[i].code}'),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == index ? 26 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: i == index
                        ? AppColors.brandYellow
                        : Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: AppColors.brandYellow.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 캐러셀 한 페이지 — 언덕 위에 선 캐릭터 한 명(배경 투명).
class _CostumeStage extends StatelessWidget {
  const _CostumeStage({required this.costume, super.key});

  final DodamCostume costume;

  @override
  Widget build(BuildContext context) => Padding(
    // 좌우 화살표와 겹치지 않도록 여백을 둔다.
    padding: const EdgeInsets.fromLTRB(56, 6, 56, 8),
    child: Column(
      children: [
        Expanded(
          child: Image.asset(
            costume.asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
        // 발밑에 깔리는 부드러운 땅 그림자 — 언덕에 서 있는 느낌을 준다.
        Container(
          width: 108,
          height: 18,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                AppColors.ink.withValues(alpha: 0.18),
                AppColors.ink.withValues(alpha: 0),
              ],
            ),
            borderRadius: BorderRadius.circular(9),
          ),
        ),
      ],
    ),
  );
}

/// 캐러셀 좌우 이동 버튼. 목록 끝에서도 반대편 항목으로 순환한다.
class _CostumeChevron extends StatelessWidget {
  const _CostumeChevron({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: true,
    label: semanticLabel,
    child: ExcludeSemantics(
      child: _Pressable(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 34, color: AppColors.ink),
        ),
      ),
    ),
  );
}

/// 오른쪽 "그림 그리기" 이젤 — 그림일기로 들어가는 큰 아동 친화 CTA.
///
/// 언덕 위에 세운 그림판(이젤)처럼 보이도록 아래에 다리 두 개를 둔다.
class _DrawEntryButton extends StatelessWidget {
  const _DrawEntryButton({required this.onTap, super.key});

  final VoidCallback? onTap;

  static Widget _leg(double angle) => Transform.rotate(
    angle: angle,
    child: Container(
      width: 13,
      height: 46,
      decoration: BoxDecoration(
        color: _treeTrunk,
        borderRadius: BorderRadius.circular(6),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: '그림 그리기. 오늘 있었던 일을 그려볼까?',
    child: ExcludeSemantics(
      child: _Pressable(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(bottom: -16, left: 40, child: _leg(0.26)),
            Positioned(bottom: -16, right: 40, child: _leg(-0.26)),
            Container(
              constraints: const BoxConstraints(
                minWidth: 300,
                maxWidth: 300,
                minHeight: 300,
              ),
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, AppColors.brandYellowSoft],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.brandYellow, width: 5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandYellow.withValues(alpha: 0.45),
                    blurRadius: 26,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/characters/costumes/dodam_draw.png',
                    height: 150,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    '그림 그리기',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '오늘 있었던 일을 그려볼까?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 이젤(그림 그리기) 아래 secondary CTA — 아이가 그린 지난 그림을 다시 보는 입구.
///
/// "그림 그리기"가 노란 이젤로 primary라, 여기는 한 단계 낮은 위계로 둔다: 흰 pill에
/// 차분한 라벤더(노랑의 보색) 액센트를 얹어, 큰 노란 이젤과 명확히 구분되면서도
/// 같은 둥근 손그림 결을 유지한다. 눌림 피드백은 이젤과 같은 [_Pressable]을 공유한다.
class _PastDrawingsButton extends StatelessWidget {
  const _PastDrawingsButton({required this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: '지난 그림 보기. 내가 그린 그림들을 다시 봐요.',
    child: ExcludeSemantics(
      child: _Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 300, maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: AppColors.lavender.withValues(alpha: 0.35),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PastDrawingsIcon(),
              SizedBox(width: 14),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '지난 그림 보기',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '내가 그린 그림 다시 보기',
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PastDrawingsIcon extends StatelessWidget {
  const _PastDrawingsIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 54,
    height: 54,
    decoration: const BoxDecoration(
      color: AppColors.lavenderSoft,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: const Icon(
      Icons.collections_rounded,
      color: AppColors.lavender,
      size: 28,
    ),
  );
}

/// 눌림 즉시 살짝 줄어드는 피드백(포인터 다운에 반응). 비활성이면 반응하지 않는다.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _setDown(bool value) {
    if (widget.onTap == null || _down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _setDown(true),
    onTapUp: (_) => _setDown(false),
    onTapCancel: () => _setDown(false),
    onTap: widget.onTap,
    child: AnimatedScale(
      scale: _down ? 0.96 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}

/// 아동 홈 배경 — 하늘 그라데이션과 언덕(해·구름·나무는 손그림 이미지로 얹는다).
class _PlaygroundScene extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_skyTop, _skyLow],
        stops: [0.0, 0.66],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Offset.zero & size, sky);

    final hillTop = h * 0.62;
    final hill = Path()
      ..moveTo(0, hillTop + h * 0.05)
      ..quadraticBezierTo(w * 0.5, hillTop - h * 0.10, w, hillTop + h * 0.03)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final grass = Paint()
      ..shader =
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_grass, _grassDeep],
          ).createShader(
            Rect.fromLTWH(0, hillTop - h * 0.1, w, h - hillTop + h * 0.1),
          );
    canvas.drawPath(hill, grass);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 하늘·언덕 위에 얹는 손그림 장식(해·구름·나무). 장식이라 터치를 막지 않는다.
class _SceneDecor extends StatelessWidget {
  const _SceneDecor();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        return Stack(
          children: [
            Positioned(
              top: -h * 0.03,
              left: -w * 0.03,
              width: w * 0.32,
              child: Image.asset('assets/scene/sun.png', fit: BoxFit.contain),
            ),
            Positioned(
              top: h * 0.14,
              right: w * 0.06,
              width: w * 0.17,
              child: Image.asset('assets/scene/cloud.png', fit: BoxFit.contain),
            ),
            Positioned(
              bottom: h * 0.08,
              right: w * 0.02,
              height: h * 0.34,
              child: Image.asset('assets/scene/tree.png', fit: BoxFit.contain),
            ),
          ],
        );
      },
    ),
  );
}
