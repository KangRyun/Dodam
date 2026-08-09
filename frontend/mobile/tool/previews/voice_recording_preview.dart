import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const VoiceRecordingPreviewApp());
}

// 백엔드 없이 질문과 음성 녹음 UI 흐름을 확인하는 개발용 진입점
final class VoiceRecordingPreviewApp extends StatelessWidget {
  const VoiceRecordingPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '도담 음성 답변 미리보기',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.leaf,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.canvas,
    ),
    home: const _VoiceRecordingPreviewLauncher(),
  );
}

// 그림 화면의 뒤로가기 목적지를 제공하는 미리보기 시작 화면
final class _VoiceRecordingPreviewLauncher extends StatefulWidget {
  const _VoiceRecordingPreviewLauncher();

  @override
  State<_VoiceRecordingPreviewLauncher> createState() =>
      _VoiceRecordingPreviewLauncherState();
}

final class _VoiceRecordingPreviewLauncherState
    extends State<_VoiceRecordingPreviewLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openDrawing();
    });
  }

  Future<void> _openDrawing() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const DrawingScreen(
        childId: '3',
        conversationRepository: MockConversationRepository(),
        conversationId: 8001,
        basisAnalysisId: 7001,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: _openDrawing,
        child: const Text('음성 녹음 미리보기 다시 열기'),
      ),
    ),
  );
}
