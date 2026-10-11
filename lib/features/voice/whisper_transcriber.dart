import 'dart:async';
import 'dart:io';

import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import '../../core/ai/ai_failure.dart';
import 'transcriber.dart';
import 'wav_recorder.dart';

/// On-device whisper.cpp via whisper_flutter_new. The `tiny` English model
/// downloads to app storage on first use (never bundled — keeps the APK
/// small and the model out of the repo).
class WhisperLocalTranscriber implements Transcriber {
  WhisperLocalTranscriber();

  final _events = StreamController<TranscriptEvent>.broadcast();
  final _recorder = WavRecorder();
  Whisper? _whisper;

  /// Lazily built — the Whisper() constructor fetches the model if absent.
  Whisper get _w => _whisper ??= Whisper(
    model: WhisperModel.tiny,
    downloadHost: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main',
  );

  @override
  EngineInfo get info =>
      const EngineInfo('whisper', 'Whisper tiny · on-device', true);

  @override
  Future<bool> get available async {
    try {
      await _w.getVersion().timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

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

  /// Post-hoc transcription — record first, transcribe on stop. The orb is
  /// in "thinking" while this runs.
  @override
  Future<void> stop() async {
    final p = await _recorder.stop();
    if (p == null) {
      _events.add(
        const TranscriptError(BadResponseFailure('No audio captured')),
      );
      return;
    }
    final sw = Stopwatch()..start();
    try {
      final raw = await _w.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: p,
          isNoTimestamps: true,
          isTranslate: false,
          splitOnWord: false,
        ),
      );
      // Whisper emits bracketed markers ([MUSIC], (silence), [BLANK_AUDIO])
      // for non-speech audio — strip them before judging emptiness.
      final text = raw
          .toString()
          .replaceAll(RegExp(r'[\[(][^\])]*[\])]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      _events.add(
        text.isEmpty
            ? const TranscriptError(BadResponseFailure('Nothing was heard'))
            : FinalEvent(
                '[${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $text',
              ),
      );
    } catch (e) {
      _events.add(
        TranscriptError(BadResponseFailure('Whisper failed: ${e.runtimeType}')),
      );
    } finally {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    }
  }
}
