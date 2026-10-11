import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import 'groq_transcriber.dart';
import 'system_transcriber.dart';
import 'transcriber.dart';
import 'whisper_transcriber.dart';

/// Engine ids persisted in settings.
enum EngineChoice { whisper, system, groq }

/// Selected engine (persisted); falls through to the first available engine
/// when the chosen one can't run.
final engineChoiceProvider =
    NotifierProvider<EngineChoiceNotifier, EngineChoice>(
      EngineChoiceNotifier.new,
    );

class EngineChoiceNotifier extends Notifier<EngineChoice> {
  static const _key = 'voiceEngine';

  @override
  EngineChoice build() {
    _load();
    return EngineChoice.whisper;
  }

  Future<void> _load() async {
    final box = await Hive.openBox('receipts_settings');
    final i = (box.get(_key) as num?)?.toInt();
    if (i != null && i < EngineChoice.values.length) {
      state = EngineChoice.values[i];
    }
  }

  Future<void> set(EngineChoice c) async {
    state = c;
    final box = await Hive.openBox('receipts_settings');
    await box.put(_key, c.index);
  }
}

/// Constructs the selected transcriber with the pieces it needs (Groq key).
final transcriberProvider = Provider<Transcriber>((ref) {
  final choice = ref.watch(engineChoiceProvider);
  final keys = ref.watch(configuredKeysProvider).value ?? const {};
  return switch (choice) {
    EngineChoice.groq when keys.containsKey(AiProvider.groq) =>
      GroqWhisperTranscriber(apiKey: keys[AiProvider.groq]!),
    EngineChoice.groq => SystemTranscriber(), // picked but no key → fall back
    EngineChoice.system => SystemTranscriber(),
    EngineChoice.whisper => WhisperLocalTranscriber(),
  };
});

/// All engines with availability — powers the Settings picker (dimmed rows).
final engineListProvider = FutureProvider<List<(Transcriber, bool)>>((
  ref,
) async {
  final keys = ref.watch(configuredKeysProvider).value ?? const {};
  final engines = <Transcriber>[
    WhisperLocalTranscriber(),
    SystemTranscriber(),
    if (keys.containsKey(AiProvider.groq))
      GroqWhisperTranscriber(apiKey: keys[AiProvider.groq]!),
  ];
  return [for (final e in engines) (e, await e.available)];
});
