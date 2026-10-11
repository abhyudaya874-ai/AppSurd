import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 16kHz mono WAV capture used by the post-hoc engines (Whisper local,
/// Groq cloud). Level events stream amplitude while recording.
class WavRecorder {
  final _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amp;
  String? _path;

  Future<bool> ensurePermission() => _recorder.hasPermission();

  /// Start recording; [onLevel] gets ~60ms amplitude 0..1 for the orb.
  Future<void> start({required void Function(double) onLevel}) async {
    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/receipts_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );
    _amp = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 60))
        .listen((a) {
          // dBFS −160..0 → perceptual 0..1.
          final l = ((a.current + 45) / 45).clamp(0.0, 1.0);
          onLevel(l);
        });
  }

  /// Stop and return the WAV path (caller deletes after transcribing).
  Future<String?> stop() async {
    await _amp?.cancel();
    _amp = null;
    await _recorder.stop();
    return _path;
  }

  Future<void> cancel() async {
    await _amp?.cancel();
    await _recorder.cancel();
    if (_path != null) {
      final f = File(_path!);
      if (f.existsSync()) f.deleteSync();
      _path = null;
    }
  }

  Future<void> dispose() async {
    await _amp?.cancel();
    await _recorder.dispose();
  }
}
