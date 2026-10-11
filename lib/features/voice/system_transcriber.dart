import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import '../../core/ai/ai_failure.dart';
import 'transcriber.dart';

/// Android's built-in recognizer via speech_to_text — streams partials and
/// sound levels. Note: it may use the network depending on the device, so
/// it's labelled "System recognizer", never "on-device".
class SystemTranscriber implements Transcriber {
  SystemTranscriber() : _stt = SpeechToText();
  final SpeechToText _stt;

  final _events = StreamController<TranscriptEvent>.broadcast();
  bool _ready = false;

  @override
  EngineInfo get info =>
      const EngineInfo('system', 'System recognizer', false);

  @override
  Future<bool> get available async =>
      _ready || (_ready = await _stt.initialize());

  @override
  Stream<TranscriptEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (!await available) {
      _events.add(const TranscriptError(
          BadResponseFailure('System recognizer unavailable')));
      return;
    }
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
      onSoundLevelChange: (level) {
        // speech_to_text reports ~-2..+10 dB-ish; squash into 0..1.
        final l = ((level + 2) / 12).clamp(0.0, 1.0);
        _events.add(LevelEvent(l));
      },
      onResult: (r) {
        if (r.finalResult) {
          _events.add(FinalEvent(r.recognizedWords));
        } else {
          _events.add(PartialEvent(r.recognizedWords));
        }
      },
    );
  }

  @override
  Future<void> stop() => _stt.stop();

  Future<void> dispose() => _events.close();
}
