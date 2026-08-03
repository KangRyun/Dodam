import 'package:flutter/foundation.dart';

import '../../../core/network/api_failure_presentation.dart';
import '../data/dto/data_retention_dtos.dart';
import '../domain/repositories/data_retention_repository.dart';

/// 데이터 보관 정책 조회의 진행 상태.
enum DataRetentionStatus { loading, ready, error }

/// 데이터 보관 정책 조회·편집·저장 상태를 관리한다.
///
/// 화면은 선택값 검증(`noticeDaysBefore < retentionDays`)이나 보관 기간을
/// 줄였을 때 안내 시점을 다시 맞추는 클램프를 직접 하지 않는다. 그 판단을 여기
/// 한곳에 모아, 화면은 [canSave]와 옵션 목록만 보고 그린다.
///
/// 계약: `docs/api/data-retention-policy-contract.md`
final class DataRetentionController extends ChangeNotifier {
  DataRetentionController(this._repository);

  final DataRetentionRepository _repository;

  /// 화면에 항상 노출하는 보관 기간 후보(일). 서버가 임의 값을 저장할 수 있어
  /// 프리셋은 편의값일 뿐이며, 조회된 값이 프리셋에 없으면 그 값도 후보에 더한다.
  static const List<int> retentionPresets = [30, 90, 180, 365];

  /// 만료 안내 시점 후보(일 전). 보관 기간보다 짧은 값만 유효하다.
  static const List<int> noticePresets = [7, 14, 30];

  DataRetentionStatus _status = DataRetentionStatus.loading;
  Object? _error;

  int _retentionDays = 0;
  int _noticeDaysBefore = 0;
  String _policyStatus = '';

  // 저장 성공 시점의 값. 편집값과 비교해 "바뀐 게 있는지"(dirty)를 판단한다.
  int _savedRetentionDays = 0;
  int _savedNoticeDaysBefore = 0;

  bool _isSaving = false;
  Object? _saveError;
  bool _disposed = false;
  int _generation = 0;

  DataRetentionStatus get status => _status;
  Object? get error => _error;

  int get retentionDays => _retentionDays;
  int get noticeDaysBefore => _noticeDaysBefore;
  String get policyStatus => _policyStatus;

  /// 보관 기간 수치가 아직 확정 전(잠정)인지. 화면이 잠정 안내를 띄우는 기준.
  bool get isProvisional => _policyStatus == 'PROVISIONAL';

  bool get isSaving => _isSaving;

  /// 조회된 값이 프리셋에 없을 수 있으므로(팀원이 API로 임의 값 저장 등), 조회값을
  /// 후보에 합쳐 오름차순으로 돌려준다. 화면은 이 목록으로 칩을 그린다.
  List<int> get retentionOptions =>
      _optionsWith(retentionPresets, [_savedRetentionDays, _retentionDays]);

  List<int> get noticeOptions =>
      _optionsWith(noticePresets, [_savedNoticeDaysBefore, _noticeDaysBefore]);

  /// 안내 시점 후보가 현재 보관 기간에서 유효한지(짧아야 함).
  bool isNoticeOptionEnabled(int noticeDays) => noticeDays < _retentionDays;

  /// 현재 편집값이 계약 불변식을 만족하는지(안내 시점 < 보관 기간, 0 이상).
  bool get isNoticeValid =>
      _noticeDaysBefore >= 0 && _noticeDaysBefore < _retentionDays;

  /// 저장 이후 편집으로 값이 바뀌었는지.
  bool get isDirty =>
      _retentionDays != _savedRetentionDays ||
      _noticeDaysBefore != _savedNoticeDaysBefore;

  /// 저장 버튼을 열 수 있는지. 준비 완료 + 바뀐 값 + 유효 + 저장 중 아님.
  bool get canSave =>
      _status == DataRetentionStatus.ready &&
      isDirty &&
      isNoticeValid &&
      !_isSaving;

  /// 저장 실패 시 화면에 띄울 문구. 실패가 없으면 `null`.
  String? get saveFailureMessage {
    final error = _saveError;
    if (error == null) return null;
    return ApiFailurePresentation.of(error).message;
  }

  Future<void> load() async {
    final generation = ++_generation;
    _status = DataRetentionStatus.loading;
    _error = null;
    _notify();

    try {
      final policy = await _repository.getDataRetentionPolicy();
      if (_disposed || generation != _generation) return;
      _applyLoaded(policy);
      _status = DataRetentionStatus.ready;
      _notify();
    } on Object catch (error) {
      if (_disposed || generation != _generation) return;
      _status = DataRetentionStatus.error;
      _error = error;
      _notify();
    }
  }

  /// 보관 기간을 바꾼다. 새 기간보다 안내 시점이 길거나 같아지면(만료 후 안내가
  /// 되면) 안내 시점을 유효한 가장 큰 값으로 다시 맞춘다(계약 불변식 유지).
  void setRetentionDays(int days) {
    if (days == _retentionDays) return;
    _retentionDays = days;
    if (_noticeDaysBefore >= days) {
      _noticeDaysBefore = _largestNoticeBelow(days);
    }
    _clearSaveError();
    _notify();
  }

  void setNoticeDaysBefore(int days) {
    if (days == _noticeDaysBefore) return;
    _noticeDaysBefore = days;
    _clearSaveError();
    _notify();
  }

  /// 두 값을 저장하고 성공 여부를 반환한다. [canSave]가 거짓이면 보내지 않는다.
  Future<bool> save() async {
    if (!canSave) return false;

    final generation = ++_generation;
    _isSaving = true;
    _saveError = null;
    _notify();

    try {
      final saved = await _repository.updateDataRetentionPolicy(
        retentionDays: _retentionDays,
        noticeDaysBefore: _noticeDaysBefore,
      );
      if (_disposed || generation != _generation) return false;
      _applyLoaded(saved);
      _isSaving = false;
      _notify();
      return true;
    } on Object catch (error) {
      if (_disposed || generation != _generation) return false;
      _isSaving = false;
      _saveError = error;
      _notify();
      return false;
    }
  }

  void _applyLoaded(DataRetentionPolicyDto policy) {
    _retentionDays = policy.retentionDays;
    _noticeDaysBefore = policy.noticeDaysBefore;
    _policyStatus = policy.policyStatus;
    _savedRetentionDays = policy.retentionDays;
    _savedNoticeDaysBefore = policy.noticeDaysBefore;
  }

  /// [days]보다 작은 안내 시점 중 가장 큰 값. 프리셋에 없으면 `days - 1`로 맞춘다
  /// (0 미만이 되지 않게 막는다).
  int _largestNoticeBelow(int days) {
    final below = noticePresets.where((value) => value < days);
    if (below.isNotEmpty) return below.reduce((a, b) => a > b ? a : b);
    return days - 1 < 0 ? 0 : days - 1;
  }

  List<int> _optionsWith(List<int> presets, List<int> extras) {
    final values = {...presets, ...extras.where((value) => value >= 0)};
    final sorted = values.toList()..sort();
    return List<int>.unmodifiable(sorted);
  }

  void _clearSaveError() {
    // 값을 다시 고르는 순간 이전 저장 실패 문구를 지운다. 남겨두면 방금 고친
    // 값에 대한 오류처럼 읽힌다.
    if (_saveError != null) _saveError = null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
