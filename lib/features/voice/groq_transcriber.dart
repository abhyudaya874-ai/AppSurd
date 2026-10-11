import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/ai/ai_failure.dart';
import '../../core/ai/model_catalog.dart';
import 'transcriber.dart';
import 'wav_recorder.dart';

/// Groq's hosted Whisper endpoint — OpenAI-style /audio/transcriptions.
/// CLOUD engine: the UI labels it clearly; audio leaves the device ONLY
/// when this engine is selected.
class GroqWhisperTranscriber implements Transcriber {
  GroqWhisperTranscriber({required this.apiKey});
  final String apiKey;

  final _events = StreamController<TranscriptEvent>.broadcast();
  final _recorder = WavRecorder();
  String? _path;

  @override
  EngineInfo get info =>
      const EngineInfo('groq', 'Groq Whisper · cloud', false);

  @override
  Future<bool> get available async => apiKey.isNotEmpty;

  @override
  Stream<TranscriptEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (!await _recorder.ensurePermission()) {
      _events.add(
        const TranscriptError(AuthFailure('Microphone permission denied')),
      );
      return;
    }
    await _recorder.start(onLevel: (l) => _events.add(LevelEvent(l)));
  }

  @override
  Future<void> stop() async {
    _path = await _recorder.stop();
    final p = _path;
    if (p == null) {
      _events.add(
        const TranscriptError(BadResponseFailure('No audio captured')),
      );
      return;
    }
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final res = await dio.post<Map<String, dynamic>>(
        '${AiProvider.groq.baseUrl}/audio/transcriptions',
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
        data: FormData.fromMap({
          'model': 'whisper-large-v3-turbo',
          'response_format': 'json',
          'file': await MultipartFile.fromFile(p, filename: 'proof.wav'),
        }),
      );
      final text = res.data?['text'] as String? ?? '';
      _events.add(
        text.isEmpty
            ? const TranscriptError(BadResponseFailure('Nothing was heard'))
            : FinalEvent(text),
      );
    } on DioException catch (e) {
      _events.add(
        TranscriptError(switch (e.response?.statusCode) {
          401 || 403 => const AuthFailure(),
          429 => const RateLimitFailure(),
          _ => const NetworkFailure(),
        }),
      );
    } finally {
      // Privacy: the temp audio is deleted right after transcription.
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
      _path = null;
    }
  }
}
