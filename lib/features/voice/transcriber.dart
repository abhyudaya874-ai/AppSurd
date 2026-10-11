import '../../core/ai/ai_failure.dart';

/// One transcription engine contract — three implementations behind it
/// (on-device Whisper, Android recognizer, Groq cloud). Everything voice in
/// the app talks to this interface.
sealed class TranscriptEvent {
  const TranscriptEvent();
}

/// Live mic amplitude 0..1 (~60ms cadence) — drives the orb's distortion.
class LevelEvent extends TranscriptEvent {
  const LevelEvent(this.level);
  final double level;
}

/// A still-being-spoken transcript (system recognizer streams these).
class PartialEvent extends TranscriptEvent {
  const PartialEvent(this.text);
  final String text;
}

/// Engine is done; this is the transcript to use.
class FinalEvent extends TranscriptEvent {
  const FinalEvent(this.text);
  final String text;
}

class TranscriptError extends TranscriptEvent {
  const TranscriptError(this.failure);
  final AiFailure failure;
}

/// Engine metadata — the result chip always shows who transcribed.
class EngineInfo {
  const EngineInfo(this.id, this.label, this.onDevice);
  final String id;

  /// e.g. "Whisper tiny · on-device" — never claim on-device for cloud.
  final String label;
  final bool onDevice;
}

abstract class Transcriber {
  EngineInfo get info;

  /// Whether this engine can run right now (model downloaded, key present…).
  Future<bool> get available;

  Stream<TranscriptEvent> get events;

  /// Start listening. May emit [TranscriptError] instead of events.
  Future<void> start();

  /// Stop listening; engines that transcribe post-hoc emit [FinalEvent]
  /// when processing finishes.
  Future<void> stop();
}
