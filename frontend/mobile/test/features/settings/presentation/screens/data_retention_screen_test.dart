import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/settings/data/dto/data_retention_dtos.dart';
import 'package:dodam/features/settings/domain/repositories/data_retention_repository.dart';
import 'package:dodam/features/settings/presentation/screens/data_retention_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataRetentionScreen', () {
    testWidgets('조회 후 현재 선택값을 보여준다', (tester) async {
      await _pumpScreen(tester, _FakeDataRetentionRepository());

      expect(find.text('180일'), findsOneWidget);
      expect(find.text('30일 전'), findsOneWidget);
    });

    testWidgets('값을 바꾸기 전에는 저장 버튼이 비활성, 바꾸면 활성이 된다', (tester) async {
      await _pumpScreen(tester, _FakeDataRetentionRepository());

      VoidCallback? saveOnPressed() => tester
          .widget<AppButton>(find.byKey(const ValueKey('data-retention-save')))
          .onPressed;

      expect(saveOnPressed(), isNull);

      await tester.tap(find.byKey(const ValueKey('data-retention-days-90')));
      await tester.pump();

      expect(saveOnPressed(), isNotNull);
    });

    testWidgets('개인정보 처리방침 링크는 처리방침 주소를 연다', (tester) async {
      String? capturedTitle;
      Uri? capturedUrl;

      await _pumpScreen(
        tester,
        _FakeDataRetentionRepository(),
        openPrivacyPolicy: (context, title, url) {
          capturedTitle = title;
          capturedUrl = url;
        },
      );

      final link = find.byKey(const ValueKey('data-retention-privacy-link'));
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pump();

      expect(capturedTitle, '개인정보 처리방침');
      expect(capturedUrl, isNotNull);
      expect(capturedUrl!.path.endsWith('/privacy/'), isTrue);
    });

    testWidgets('조회에 실패하면 실패 화면을 보여준다', (tester) async {
      await _pumpScreen(
        tester,
        _FakeDataRetentionRepository(loadError: Exception('boom')),
      );

      expect(find.text('보관 설정을 불러오지 못했어요'), findsOneWidget);
    });
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  DataRetentionRepository repository, {
  void Function(BuildContext, String, Uri)? openPrivacyPolicy,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DataRetentionScreen(
        repository: repository,
        openPrivacyPolicy: openPrivacyPolicy,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeDataRetentionRepository implements DataRetentionRepository {
  _FakeDataRetentionRepository({this.loadError});

  final Object? loadError;

  @override
  Future<DataRetentionPolicyDto> getDataRetentionPolicy() async {
    if (loadError != null) throw loadError!;
    return const DataRetentionPolicyDto(
      retentionDays: 180,
      noticeDaysBefore: 30,
      policyStatus: 'PROVISIONAL',
    );
  }

  @override
  Future<DataRetentionPolicyDto> updateDataRetentionPolicy({
    required int retentionDays,
    required int noticeDaysBefore,
  }) async => DataRetentionPolicyDto(
    retentionDays: retentionDays,
    noticeDaysBefore: noticeDaysBefore,
    policyStatus: 'PROVISIONAL',
  );
}
