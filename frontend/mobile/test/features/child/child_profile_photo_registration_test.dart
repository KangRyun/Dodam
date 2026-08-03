import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_profile_image_repository.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:dodam/features/child/presentation/screens/child_registration_screen.dart';
import 'package:dodam/features/drawing/domain/photo_picker_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  testWidgets('사진 없이 신규 등록하면 profileImageFileId 없이 BASE로 생성한다', (tester) async {
    final childRepository = _ChildRepository();
    final controller = GuardianChildController(childRepository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChildRegistrationScreen(
          controller: controller,
          profileImageRepository: _ProfileRepository(),
          photoPicker: _PhotoPicker(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('child-nickname')), '새봄');
    await tester.tap(find.byKey(const ValueKey('child-birth-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('submit-child-registration'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(childRepository.createRequests, hasLength(1));
    expect(
      childRepository.createRequests.single.toJson(),
      isNot(contains('profileImageFileId')),
    );
    expect(childRepository.createRequests.single.preferredCharacter, 'BASE');
  });

  testWidgets('등록·편집 화면은 캐릭터 선택을 숨기고 선택적 사진 영역을 표시한다', (tester) async {
    final childRepository = _ChildRepository();
    final controller = GuardianChildController(childRepository);
    addTearDown(controller.dispose);

    await _pumpEditor(
      tester,
      controller: controller,
      profileRepository: _ProfileRepository(),
    );

    expect(find.text('아이와 함께할 친구를 골라주세요'), findsNothing);
    expect(find.byKey(const ValueKey('character-BASE')), findsNothing);
    expect(find.text('아이 프로필 사진'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pick-child-profile-photo')),
      findsOneWidget,
    );
  });

  testWidgets('PNG 선택 후 연속 저장해도 upload와 PATCH는 각각 한 번이며 새 ID를 연결한다', (
    tester,
  ) async {
    final childRepository = _ChildRepository();
    final controller = GuardianChildController(childRepository);
    final upload = Completer<ChildProfileImageUploadResponseDto>();
    final profileRepository = _ProfileRepository(uploadCompleter: upload);
    final picker = _PhotoPicker([
      PickedPhoto(
        bytes: _pngBytes,
        fileName: 'child.png',
        mimeType: 'image/png',
      ),
    ]);
    addTearDown(controller.dispose);

    await _pumpEditor(
      tester,
      controller: controller,
      profileRepository: profileRepository,
      picker: picker,
    );
    await tester.tap(find.byKey(const ValueKey('pick-child-profile-photo')));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);

    final submit = find.byKey(const ValueKey('submit-child-registration'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(profileRepository.uploads, hasLength(1));
    expect(
      find.byKey(const ValueKey('child-profile-photo-upload-progress')),
      findsOneWidget,
    );

    upload.complete(_uploadResponse);
    await tester.pumpAndSettle();

    expect(profileRepository.uploads, hasLength(1));
    expect(childRepository.updateRequests, hasLength(1));
    expect(
      childRepository.updateRequests.single.profileImage,
      isA<ProfileImageReplace>().having(
        (value) => value.profileImageFileId,
        'profileImageFileId',
        'profile-file-828',
      ),
    );
  });

  testWidgets('upload 실패 후 저장 retry는 사진만 재업로드하고 PATCH는 성공 시 한 번이다', (
    tester,
  ) async {
    final childRepository = _ChildRepository();
    final controller = GuardianChildController(childRepository);
    final profileRepository = _ProfileRepository(failuresRemaining: 1);
    final picker = _PhotoPicker([
      PickedPhoto(
        bytes: _pngBytes,
        fileName: 'retry.png',
        mimeType: 'image/png',
      ),
    ]);
    addTearDown(controller.dispose);

    await _pumpEditor(
      tester,
      controller: controller,
      profileRepository: profileRepository,
      picker: picker,
    );
    await tester.tap(find.byKey(const ValueKey('pick-child-profile-photo')));
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('submit-child-registration'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(profileRepository.uploads, hasLength(1));
    expect(childRepository.updateRequests, isEmpty);
    expect(find.text('사진을 업로드하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);

    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(profileRepository.uploads, hasLength(2));
    expect(childRepository.updateRequests, hasLength(1));
  });

  testWidgets('upload 완료 전에 dispose되면 늦은 응답이 PATCH나 setState를 만들지 않는다', (
    tester,
  ) async {
    final childRepository = _ChildRepository();
    final controller = GuardianChildController(childRepository);
    final upload = Completer<ChildProfileImageUploadResponseDto>();
    final profileRepository = _ProfileRepository(uploadCompleter: upload);
    final picker = _PhotoPicker([
      PickedPhoto(
        bytes: _pngBytes,
        fileName: 'late.png',
        mimeType: 'image/png',
      ),
    ]);
    addTearDown(controller.dispose);
    await _pumpEditor(
      tester,
      controller: controller,
      profileRepository: profileRepository,
      picker: picker,
    );
    await tester.tap(find.byKey(const ValueKey('pick-child-profile-photo')));
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('submit-child-registration'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    upload.complete(_uploadResponse);
    await tester.pump();

    expect(childRepository.updateRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WEBP와 5MiB 초과 파일은 upload 전에 차단한다', (tester) async {
    final childRepository = _ChildRepository();
    final controller = GuardianChildController(childRepository);
    final profileRepository = _ProfileRepository();
    final picker = _PhotoPicker([
      PickedPhoto(
        bytes: Uint8List.fromList(const [
          0x52,
          0x49,
          0x46,
          0x46,
          0,
          0,
          0,
          0,
          0x57,
          0x45,
          0x42,
          0x50,
        ]),
        fileName: 'child.webp',
        mimeType: 'image/webp',
      ),
      PickedPhoto(
        bytes: Uint8List(5 * 1024 * 1024 + 1)
          ..setRange(0, 8, const [
            0x89,
            0x50,
            0x4e,
            0x47,
            0x0d,
            0x0a,
            0x1a,
            0x0a,
          ]),
        fileName: 'large.png',
        mimeType: 'image/png',
      ),
    ]);
    addTearDown(controller.dispose);

    await _pumpEditor(
      tester,
      controller: controller,
      profileRepository: profileRepository,
      picker: picker,
    );
    final pick = find.byKey(const ValueKey('pick-child-profile-photo'));
    await tester.tap(pick);
    await tester.pumpAndSettle();
    expect(find.text('JPEG·PNG 형식의 사진만 사용할 수 있어요.'), findsOneWidget);

    await tester.tap(pick);
    await tester.pumpAndSettle();
    expect(find.text('사진은 5MB 이하만 사용할 수 있어요.'), findsOneWidget);
    expect(profileRepository.uploads, isEmpty);
  });

  testWidgets('기존 사진 미변경은 key를 생략하고 명시적 삭제는 null로 보낸다', (tester) async {
    final childRepository = _ChildRepository();
    final controller = GuardianChildController(childRepository);
    final profileRepository = _ProfileRepository();
    addTearDown(controller.dispose);

    await _pumpEditor(
      tester,
      controller: controller,
      profileRepository: profileRepository,
    );
    var submit = find.byKey(const ValueKey('submit-child-registration'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
      childRepository.updateRequests.single.toJson(),
      isNot(contains('profileImageFileId')),
    );

    childRepository.updateRequests.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpEditor(
      tester,
      controller: controller,
      profileRepository: profileRepository,
    );
    final remove = find.byKey(const ValueKey('remove-child-profile-photo'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pump();
    submit = find.byKey(const ValueKey('submit-child-registration'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      childRepository.updateRequests.single.toJson(),
      containsPair('profileImageFileId', null),
    );
  });

  testWidgets('사진 삭제 PATCH가 실패하면 기존 사진 삭제 UI를 복원한다', (tester) async {
    final childRepository = _ChildRepository(updateFailuresRemaining: 1);
    final controller = GuardianChildController(childRepository);
    addTearDown(controller.dispose);
    await _pumpEditor(
      tester,
      controller: controller,
      profileRepository: _ProfileRepository(),
    );

    final remove = find.byKey(const ValueKey('remove-child-profile-photo'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pump();
    expect(remove, findsNothing);
    final submit = find.byKey(const ValueKey('submit-child-registration'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      childRepository.updateRequests.single.toJson(),
      containsPair('profileImageFileId', null),
    );
    expect(
      find.byKey(const ValueKey('remove-child-profile-photo')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required GuardianChildController controller,
  required _ProfileRepository profileRepository,
  PhotoPickerAdapter? picker,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChildRegistrationScreen(
        controller: controller,
        child: _child,
        profileImageRepository: profileRepository,
        photoPicker: picker,
        photoDimensionReader: (_) async => (512, 512),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _child = ChildSummaryDto(
  childId: 7,
  nickname: '민지',
  birthDate: '2020-03-02',
  age: 6,
  profileImageUrl: '/api/v1/child-profile-images/current/file',
  preferredCharacter: 'DINO',
  questionDifficulty: 'PRESCHOOL',
  tutorialStatus: 'NOT_STARTED',
  relationshipType: 'MOTHER',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

const _uploadResponse = ChildProfileImageUploadResponseDto(
  profileImageFileId: 'profile-file-828',
  contentType: 'image/png',
  fileSizeBytes: 68,
  widthPx: 512,
  heightPx: 512,
  expiresAt: '2026-08-03T12:00:00Z',
);

final class _PhotoPicker implements PhotoPickerAdapter {
  _PhotoPicker(this.photos);

  final List<PickedPhoto?> photos;
  int calls = 0;

  @override
  Future<PickedPhoto?> pickFromGallery() async => photos[calls++];

  @override
  Future<PickedPhoto?> pickFromCamera() => throw UnimplementedError();
}

final class _ProfileRepository implements ChildProfileImageRepository {
  _ProfileRepository({this.uploadCompleter, this.failuresRemaining = 0});

  final Completer<ChildProfileImageUploadResponseDto>? uploadCompleter;
  int failuresRemaining;
  final List<ChildProfileImageUpload> uploads = [];

  @override
  Future<Uint8List> downloadProfileImage(String relativeUrl) async => _pngBytes;

  @override
  Future<ChildProfileImageUploadResponseDto> uploadProfileImage(
    ChildProfileImageUpload image, {
    void Function(int sent, int total)? onSendProgress,
  }) async {
    uploads.add(image);
    onSendProgress?.call(1, 2);
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw StateError('upload failed');
    }
    return uploadCompleter?.future ?? _uploadResponse;
  }
}

final class _ChildRepository implements ChildRepository {
  _ChildRepository({this.updateFailuresRemaining = 0});

  int updateFailuresRemaining;
  final List<CreateChildRequestDto> createRequests = [];
  final List<UpdateChildRequestDto> updateRequests = [];

  @override
  Future<List<ChildSummaryDto>> getChildren() async => const [_child];

  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) async {
    updateRequests.add(request);
    if (updateFailuresRemaining > 0) {
      updateFailuresRemaining -= 1;
      throw StateError('update failed');
    }
    return _detail;
  }

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) async {
    createRequests.add(request);
    return _detail;
  }

  @override
  Future<void> deleteChild(int childId) => throw UnimplementedError();

  @override
  Future<ChildDetailDto> getChild(int childId) => throw UnimplementedError();

  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) =>
      throw UnimplementedError();

  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) => throw UnimplementedError();
}

const _detail = ChildDetailDto(
  childId: 7,
  nickname: '민지',
  birthDate: '2020-03-02',
  age: 6,
  profileImageUrl: '/api/v1/child-profile-images/current/file',
  preferredCharacter: 'DINO',
  questionDifficulty: 'PRESCHOOL',
  responseModes: ['VOICE'],
  tutorialStatus: 'NOT_STARTED',
  profileStatus: 'ACTIVE',
  relationshipType: 'MOTHER',
  createdAt: null,
);
