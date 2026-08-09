import '../../domain/preferred_character.dart';

final class ChildRecentActivityDto {
  const ChildRecentActivityDto({
    required this.lastActivityAt,
    required this.totalActivityCount,
  });

  factory ChildRecentActivityDto.fromJson(Map<String, dynamic> json) =>
      ChildRecentActivityDto(
        lastActivityAt: json['lastActivityAt'] as String?,
        totalActivityCount: json['totalActivityCount'] as int,
      );

  final String? lastActivityAt;
  final int totalActivityCount;
}

final class ChildSummaryDto {
  const ChildSummaryDto({
    required this.childId,
    required this.nickname,
    required this.birthDate,
    required this.age,
    required this.profileImageUrl,
    required this.preferredCharacter,
    required this.questionDifficulty,
    required this.tutorialStatus,
    required this.relationshipType,
    required this.recentActivity,
    this.educationStage,
  });

  factory ChildSummaryDto.fromJson(Map<String, dynamic> json) =>
      ChildSummaryDto(
        childId: json['childId'] as int,
        nickname: json['nickname'] as String,
        birthDate: json['birthDate'] as String,
        age: json['age'] as int,
        profileImageUrl: json['profileImageUrl'] as String?,
        preferredCharacter: json['preferredCharacter'] as String?,
        questionDifficulty: json['questionDifficulty'] as String,
        tutorialStatus: json['tutorialStatus'] as String,
        relationshipType: json['relationshipType'] as String,
        educationStage: json['educationStage'] as String?,
        recentActivity: ChildRecentActivityDto.fromJson(
          Map<String, dynamic>.from(json['recentActivity'] as Map),
        ),
      );

  final int childId;
  final String nickname;
  final String birthDate;
  final int age;
  final String? profileImageUrl;
  final String? preferredCharacter;
  final String questionDifficulty;
  final String tutorialStatus;
  final String relationshipType;

  /// 아이가 다니는 곳이며 고르지 않았으면 null 또는 UNKNOWN.
  final String? educationStage;

  final ChildRecentActivityDto recentActivity;

  /// 프로필 이미지(캐릭터) 갱신을 메모리에서 낙관적으로 반영하기 위한 복제
  /// (S15P11B209-505). 현재는 [preferredCharacter]만 바꿀 수 있으면 충분하다.
  ChildSummaryDto copyWith({String? preferredCharacter}) => ChildSummaryDto(
    childId: childId,
    nickname: nickname,
    birthDate: birthDate,
    age: age,
    profileImageUrl: profileImageUrl,
    preferredCharacter: preferredCharacter ?? this.preferredCharacter,
    questionDifficulty: questionDifficulty,
    tutorialStatus: tutorialStatus,
    relationshipType: relationshipType,
    educationStage: educationStage,
    recentActivity: recentActivity,
  );
}

final class ChildDetailDto {
  const ChildDetailDto({
    required this.childId,
    required this.nickname,
    required this.birthDate,
    required this.age,
    required this.profileImageUrl,
    required this.preferredCharacter,
    required this.questionDifficulty,
    required this.responseModes,
    required this.tutorialStatus,
    required this.profileStatus,
    required this.relationshipType,
    required this.createdAt,
    this.updatedAt,
  });

  factory ChildDetailDto.fromJson(Map<String, dynamic> json) => ChildDetailDto(
    childId: json['childId'] as int,
    nickname: json['nickname'] as String,
    birthDate: json['birthDate'] as String,
    age: json['age'] as int,
    profileImageUrl: json['profileImageUrl'] as String?,
    preferredCharacter: json['preferredCharacter'] as String?,
    questionDifficulty: json['questionDifficulty'] as String,
    responseModes: List<String>.from(json['responseModes'] as List),
    tutorialStatus: json['tutorialStatus'] as String,
    profileStatus: json['profileStatus'] as String,
    relationshipType: json['relationshipType'] as String,
    createdAt: json['createdAt'] as String?,
    updatedAt: json['updatedAt'] as String?,
  );

  final int childId;
  final String nickname;
  final String birthDate;
  final int age;
  final String? profileImageUrl;
  final String? preferredCharacter;
  final String questionDifficulty;
  final List<String> responseModes;
  final String tutorialStatus;
  final String profileStatus;
  final String relationshipType;
  final String? createdAt;
  final String? updatedAt;
}

final class CreateChildRequestDto {
  const CreateChildRequestDto({
    required this.nickname,
    required this.birthDate,
    required this.relationshipType,
    required this.questionDifficulty,
    required this.responseModes,
    this.preferredCharacter,
    this.profileImageFileId,
    this.educationStage,
  });
  final String nickname;
  final String birthDate;
  final String? preferredCharacter;
  final String questionDifficulty;
  final List<String> responseModes;
  final String relationshipType;
  final String? profileImageFileId;

  /// 아이가 다니는 곳이며 고르지 않았으면 `null`.
  ///
  /// **필수가 아니다.** 보내지 않으면 서버가 비운 채로 둔다 — 나이만으로 학년을
  /// 확정하지 않으려고 두는 값이라, 모르는 채로 두는 것이 정상이다.
  final String? educationStage;

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'birthDate': birthDate,
    'relationshipType': relationshipType,
    if (preferredCharacter != null)
      'preferredCharacter': normalizePreferredCharacter(preferredCharacter),
    'questionDifficulty': questionDifficulty,
    'responseModes': responseModes,
    if (profileImageFileId != null) 'profileImageFileId': profileImageFileId,
    if (educationStage != null) 'educationStage': educationStage,
  };
}

/// 아이가 다니는 곳 (S15P11B209-1010 v2).
///
/// 만 6세(72~83개월)의 발달 맥락을 나이와 **함께** 고르는 데 쓴다. 같은 6세라도 유치원에
/// 다니는 아이와 초등 1학년이 참고할 자료가 다르고, 어린이집에 다니는 아이에게는 어느 학년
/// 자료도 적용하지 않는다.
///
/// `null`(고르지 않음)이 정상이며 필수 입력이 아니다.
enum EducationStageOption {
  /// 어린이집.
  preschool('PRESCHOOL', '어린이집'),

  /// 유치원.
  kindergarten('KINDERGARTEN', '유치원'),

  /// 초등학교 1학년.
  grade1('GRADE_1', '초등학교 1학년');

  const EducationStageOption(this.wireValue, this.label);

  /// 서버에 보내는 값.
  final String wireValue;

  /// 화면에 보이는 이름.
  final String label;

  /// 서버 값에서 읽는다. 모르는 값과 `UNKNOWN`은 `null`이다.
  ///
  /// 서버는 미입력을 `UNKNOWN`으로 내보내는데, 화면에서는 "고르지 않음"과 같게 다룬다 —
  /// 둘을 나눠 보여 줄 만한 차이가 없다.
  static EducationStageOption? fromWire(String? value) {
    for (final option in EducationStageOption.values) {
      if (option.wireValue == value) return option;
    }
    return null;
  }
}

/// PATCH에서 프로필 사진의 생략/null/value를 구분한다.
sealed class ProfileImageUpdate {
  const ProfileImageUpdate();

  const factory ProfileImageUpdate.unchanged() = ProfileImageUnchanged;
  const factory ProfileImageUpdate.clear() = ProfileImageClear;
  const factory ProfileImageUpdate.replace(String profileImageFileId) =
      ProfileImageReplace;
}

final class ProfileImageUnchanged extends ProfileImageUpdate {
  const ProfileImageUnchanged();
}

final class ProfileImageClear extends ProfileImageUpdate {
  const ProfileImageClear();
}

final class ProfileImageReplace extends ProfileImageUpdate {
  const ProfileImageReplace(this.profileImageFileId);

  final String profileImageFileId;
}

final class UpdateChildRequestDto {
  const UpdateChildRequestDto({
    this.nickname,
    this.profileImage = const ProfileImageUpdate.unchanged(),
    this.preferredCharacter,
    this.questionDifficulty,
    this.responseModes,
    this.educationStage = const EducationStageUpdate.unchanged(),
  });
  final String? nickname;
  final ProfileImageUpdate profileImage;
  final String? preferredCharacter;
  final String? questionDifficulty;
  final List<String>? responseModes;

  /// 다니는 곳을 어떻게 할지.
  ///
  /// **생략과 비움을 구별해야 한다.** 보호자가 "선택하지 않을래요"를 고른 것은 값을 지우라는
  /// 뜻이고, 화면이 그 항목을 안 건드린 것은 그대로 두라는 뜻이다. 둘 다 JSON 에서는
  /// 필드가 없거나 `null` 이라, 프로필 사진과 같은 sealed 방식으로 나눈다.
  final EducationStageUpdate educationStage;

  Map<String, dynamic> toJson() => {
    if (nickname != null) 'nickname': nickname,
    if (profileImage is ProfileImageClear) 'profileImageFileId': null,
    if (profileImage case ProfileImageReplace(:final profileImageFileId))
      'profileImageFileId': profileImageFileId,
    if (preferredCharacter != null)
      'preferredCharacter': normalizePreferredCharacter(preferredCharacter),
    if (questionDifficulty != null) 'questionDifficulty': questionDifficulty,
    if (responseModes != null) 'responseModes': responseModes,
    if (educationStage is EducationStageClear) 'educationStage': null,
    if (educationStage case EducationStageReplace(:final stage))
      'educationStage': stage.wireValue,
  };
}

/// PATCH 에서 다니는 곳의 생략·비움·값을 구분한다.
sealed class EducationStageUpdate {
  const EducationStageUpdate();

  /// 이 항목을 건드리지 않는다.
  const factory EducationStageUpdate.unchanged() = EducationStageUnchanged;

  /// 값을 비운다("선택하지 않을래요").
  const factory EducationStageUpdate.clear() = EducationStageClear;

  /// 값을 바꾼다.
  const factory EducationStageUpdate.replace(EducationStageOption stage) =
      EducationStageReplace;
}

final class EducationStageUnchanged extends EducationStageUpdate {
  const EducationStageUnchanged();
}

final class EducationStageClear extends EducationStageUpdate {
  const EducationStageClear();
}

final class EducationStageReplace extends EducationStageUpdate {
  const EducationStageReplace(this.stage);

  final EducationStageOption stage;
}

final class ChildProfileImageUploadResponseDto {
  const ChildProfileImageUploadResponseDto({
    required this.profileImageFileId,
    required this.contentType,
    required this.fileSizeBytes,
    required this.widthPx,
    required this.heightPx,
    required this.expiresAt,
  });

  factory ChildProfileImageUploadResponseDto.fromJson(
    Map<String, dynamic> json,
  ) => ChildProfileImageUploadResponseDto(
    profileImageFileId: json['profileImageFileId'] as String,
    contentType: json['contentType'] as String,
    fileSizeBytes: json['fileSizeBytes'] as int,
    widthPx: json['widthPx'] as int,
    heightPx: json['heightPx'] as int,
    expiresAt: json['expiresAt'] as String,
  );

  final String profileImageFileId;
  final String contentType;
  final int fileSizeBytes;
  final int widthPx;
  final int heightPx;
  final String expiresAt;
}

final class TutorialProgressDto {
  const TutorialProgressDto({
    required this.childId,
    required this.tutorialStatus,
    required this.lastStep,
    required this.completedAt,
    required this.updatedAt,
  });
  factory TutorialProgressDto.fromJson(Map<String, dynamic> json) =>
      TutorialProgressDto(
        childId: json['childId'] as int,
        tutorialStatus: json['tutorialStatus'] as String,
        lastStep: json['lastStep'] as String?,
        completedAt: json['completedAt'] as String?,
        updatedAt: json['updatedAt'] as String,
      );
  final int childId;
  final String tutorialStatus;
  final String? lastStep;
  final String? completedAt;
  final String updatedAt;
}

final class UpdateTutorialRequestDto {
  const UpdateTutorialRequestDto({required this.tutorialStatus, this.lastStep});
  final String tutorialStatus;
  final String? lastStep;
  Map<String, dynamic> toJson() => {
    'tutorialStatus': tutorialStatus,
    if (lastStep != null) 'lastStep': lastStep,
  };
}
