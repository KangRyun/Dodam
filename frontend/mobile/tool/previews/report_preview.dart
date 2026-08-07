import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/report/data/dto/report_dtos.dart';
import 'package:dodam/features/report/data/repositories/mock_report_repository.dart';
import 'package:dodam/features/report/domain/repositories/report_repository.dart';
import 'package:dodam/features/report/presentation/screens/report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 관찰 리포트 화면을 백엔드·로그인 없이 띄운다.
///
/// 그림일기(비-HTP) 표본으로 섹션 구성과 간격을 눈으로 확인하는 용도다.
/// 그림은 실제 이미지가 있어야 크기 감이 잡히므로 번들 자산을 대신 물린다.
///
/// 실행: flutter run -t tool/previews/report_preview.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReportPreview());
}

class ReportPreview extends StatelessWidget {
  const ReportPreview({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ReportScreen(
      reportId: '501',
      repository: const _PreviewReportRepository(),
      voiceAnswerPlaybackRepository: const _PreviewPlaybackRepository(),
      voiceAnswerAudioPlayerFactory: _SilentVoiceAnswerAudioPlayer.new,
    ),
  );
}

/// Mock 표본을 그대로 흘려보내되 그림만 실제 자산 bytes로 바꿔 준다.
/// [MockReportRepository.downloadImage]는 빈 bytes를 주어 자리표시자만 보인다.
final class _PreviewReportRepository implements ReportRepository {
  const _PreviewReportRepository();

  static const _mock = MockReportRepository();

  @override
  Future<Uint8List> downloadImage(String imageUrl) async {
    final data = await rootBundle.load('assets/scene/tree.png');
    return data.buffer.asUint8List();
  }

  @override
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  }) => _mock.getReports(childId, filter: filter);

  @override
  Future<ReportDetailDto> getReport(int reportId) => _mock.getReport(reportId);

  @override
  Future<ReportGenerationStatusDto> getGenerationStatus(int reportId) =>
      _mock.getGenerationStatus(reportId);

  @override
  Future<ReportGenerationStatusDto> regenerateReport(
    int reportId, {
    required String idempotencyKey,
  }) => _mock.regenerateReport(reportId, idempotencyKey: idempotencyKey);

  @override
  Future<ReportExportDto> requestExport(
    int reportId, {
    required String idempotencyKey,
  }) => _mock.requestExport(reportId, idempotencyKey: idempotencyKey);

  @override
  Future<Uint8List> downloadExport(String downloadUrl) =>
      _mock.downloadExport(downloadUrl);

  @override
  Future<AnalysisStatusDto> getAnalysisStatus(int analysisId) =>
      _mock.getAnalysisStatus(analysisId);

  @override
  Future<AnalysisAcceptedDto> retryAnalysis(
    int analysisId, {
    required String idempotencyKey,
  }) => _mock.retryAnalysis(analysisId, idempotencyKey: idempotencyKey);
}

/// 재생 버튼이 보이고 눌리는지까지만 확인하면 되므로 소리는 내지 않는다.
final class _PreviewPlaybackRepository
    implements VoiceAnswerPlaybackRepository {
  const _PreviewPlaybackRepository();

  @override
  Future<VoiceAnswerAudio> loadVoiceAnswerAudio(
    int messageId, {
    VoiceAnswerPlaybackCancellation? cancellation,
  }) async => VoiceAnswerAudio(
    bytes: Uint8List.fromList(const [0]),
    mimeType: 'audio/mpeg',
  );
}

final class _SilentVoiceAnswerAudioPlayer implements VoiceAnswerAudioPlayer {
  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) =>
      Future<void>.delayed(const Duration(seconds: 1));

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
