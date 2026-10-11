import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'model_catalog.dart';

/// Where API keys live: flutter_secure_storage (in-app entry) with a
/// --dart-define-from-file fallback (env.json at build time). Keys are never
/// logged and only ever sent to their own provider's base URL.
class ApiKeyStore {
  ApiKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _keyName(AiProvider p) => 'receipts_key_${p.id}';

  /// Compile-time fallback read from env.json via --dart-define-from-file.
  static String _defineFor(AiProvider p) => switch (p) {
        AiProvider.groq => const String.fromEnvironment('GROQ_API_KEY'),
        AiProvider.nvidia => const String.fromEnvironment('NVIDIA_API_KEY'),
        AiProvider.openrouter =>
          const String.fromEnvironment('OPENROUTER_API_KEY'),
      };

  /// Effective key for a provider: secure storage wins, dart-define fills in.
  Future<String?> read(AiProvider p) async {
    final stored = await _storage.read(key: _keyName(p));
    if (stored != null && stored.isNotEmpty) return stored;
    final define = _defineFor(p);
    return define.isEmpty ? null : define;
  }

  Future<void> write(AiProvider p, String key) async {
    if (key.isEmpty) {
      await _storage.delete(key: _keyName(p));
    } else {
      await _storage.write(key: _keyName(p), value: key);
    }
  }

  /// Snapshot of which providers currently have a usable key.
  Future<Map<AiProvider, String>> readAll() async {
    final out = <AiProvider, String>{};
    for (final p in AiProvider.values) {
      final k = await read(p);
      if (k != null) out[p] = k;
    }
    return out;
  }
}

/// Riverpod view of configured keys so the UI can dim locked providers.
final apiKeyStoreProvider = Provider<ApiKeyStore>((ref) => ApiKeyStore());

/// Holds the currently-configured keys; rebuilt when settings save.
final configuredKeysProvider =
    AsyncNotifierProvider<ConfiguredKeys, Map<AiProvider, String>>(
        ConfiguredKeys.new);

/// Loads and refreshes the {provider: key} map used by router + settings UI.
class ConfiguredKeys extends AsyncNotifier<Map<AiProvider, String>> {
  @override
  Future<Map<AiProvider, String>> build() =>
      ref.watch(apiKeyStoreProvider).readAll();

  Future<void> save(AiProvider provider, String key) async {
    await ref.read(apiKeyStoreProvider).write(provider, key);
    state = const AsyncLoading();
    state = AsyncData(await ref.read(apiKeyStoreProvider).readAll());
  }
}
