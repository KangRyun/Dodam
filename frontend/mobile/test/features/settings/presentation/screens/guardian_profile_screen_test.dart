import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/settings/presentation/screens/guardian_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const initialUser = AuthenticatedUser(
    id: '1',
    provider: AuthProvider.google,
    providerUserId: 'google-1',
    role: UserRole.guardian,
    onboardingCompleted: true,
    email: 'guardian@dodam.test',
    nickname: '기존 보호자',
  );

  testWidgets('프로필을 조회하고 변경한 닉네임을 저장한다', (tester) async {
    String? savedNickname;
    await tester.pumpWidget(
      MaterialApp(
        home: GuardianProfileScreen(
          initialUser: initialUser,
          loadProfile: () async => initialUser,
          updateProfile: (nickname) async {
            savedNickname = nickname;
            return initialUser.copyWith(nickname: nickname);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('guardian@dodam.test'), findsOneWidget);
    expect(find.text('구글 계정'), findsOneWidget);

    final nickname = find.byKey(const ValueKey('guardian-profile-nickname'));
    await tester.enterText(nickname, '수정한 보호자');
    final saveButton = find.text('저장하기');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(savedNickname, '수정한 보호자');
    expect(find.text('내 정보를 저장했어요.'), findsOneWidget);
  });

  testWidgets('빈 닉네임은 저장하지 않는다', (tester) async {
    var updateCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GuardianProfileScreen(
          initialUser: initialUser,
          loadProfile: () async => initialUser,
          updateProfile: (nickname) async {
            updateCount++;
            return initialUser;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('guardian-profile-nickname')),
      ' ',
    );
    final saveButton = find.text('저장하기');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(find.text('닉네임을 입력해 주세요.'), findsOneWidget);
    expect(updateCount, 0);
  });
}
