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
  });
  final String nickname;
  final String birthDate;
  final String? preferredCharacter;
  final String questionDifficulty;
  final List<String> responseModes;
  final String relationshipType;
  final String? profileImageFileId;

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'birthDate': birthDate,
    'relationshipType': relationshipType,
    if (preferredCharacter != null)
      'preferredCharacter': normalizePreferredCharacter(preferredCharacter),
    'questionDifficulty': questionDifficulty,
    'responseModes': responseModes,
    if (profileImageFileId != null) 'profileImageFileId': profileImageFileId,
  };
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
  });
  final String? nickname;
  final ProfileImageUpdate profileImage;
  final String? preferredCharacter;
  final String? questionDifficulty;
  final List<String>? responseModes;

  Map<String, dynamic> toJson() => {
    if (nickname != null) 'nickname': nickname,
    if (profileImage is ProfileImageClear) 'profileImageFileId': null,
    if (profileImage case ProfileImageReplace(:final profileImageFileId))
      'profileImageFileId': profileImageFileId,
    if (preferredCharacter != null)
      'preferredCharacter': normalizePreferredCharacter(preferredCharacter),
    if (questionDifficulty != null) 'questionDifficulty': questionDifficulty,
    if (responseModes != null) 'responseModes': responseModes,
  };
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
