import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'exa_client.dart';
import 'search_models.dart';
import 'tavily_client.dart';

/// User's forced choice from the "Search ▾" chip — Auto picks by intent.
enum SearchOverride { auto, tavily, exa, off }

/// Which search agentic level is active — set by the "Agentic ▾" chip.
enum AgenticMode { off, search, deep }

/// Runtime search keys — secure storage + `--dart-define` (`TAVILY_API_KEY`,
/// `EXA_API_KEY`). Build-time values act as defaults when secure storage is
/// empty.
final searchKeysProvider =
    AsyncNotifierProvider<SearchKeysNotifier, Map<String, String>>(
      SearchKeysNotifier.new,
    );

class SearchKeysNotifier extends AsyncNotifier<Map<String, String>> {
  static const _store = FlutterSecureStorage();

  @override
  Future<Map<String, String>> build() async {
    return {
      'tavily':
          await _store.read(key: 'tavily_api_key') ??
          const String.fromEnvironment('TAVILY_API_KEY'),
      'exa':
          await _store.read(key: 'exa_api_key') ??
          const String.fromEnvironment('EXA_API_KEY'),
    }..removeWhere((_, v) => v.isEmpty);
  }

  Future<void> save(String engine, String key) async {
    await _store.write(key: '${engine}_api_key', value: key.trim());
    ref.invalidateSelf();
  }

  Future<bool> testKey(String engine) async {
    final key = state.value?[engine];
    if (key == null || key.isEmpty) return false;
    try {
      return engine == 'tavily'
          ? await TavilyClient(apiKey: key).ping()
          : await ExaClient(apiKey: key).ping();
    } catch (_) {
      return false;
    }
  }
}

/// Routes a query to the right provider by intent, with graceful fallback.
/// news/factcheck/extract → Tavily; semantic/similar/corroborate → Exa;
/// missing key or a failed call falls over to the other. No keys → null.
class SearchRouter {
  SearchRouter(this._keys);
  final Map<String, String> _keys;

  /// Run [query] honoring the user's override; returns (hits, providerLabel).
  Future<(List<SearchHit>, String?)> run(
    SearchQuery query, {
    SearchOverride override_ = SearchOverride.auto,
  }) async {
    if (override_ == SearchOverride.off) return (<SearchHit>[], null);

    final tavKey = _keys['tavily'];
    final exaKey = _keys['exa'];

    // Preferred provider by intent.
    final wantTavily = switch (query.intent) {
      SearchIntent.news ||
      SearchIntent.factcheck ||
      SearchIntent.extract => true,
      _ => false,
    };

    // Forced override wins outright.
    if (override_ == SearchOverride.tavily && tavKey != null) {
      return (await _tavily(tavKey, query), 'Tavily');
    }
    if (override_ == SearchOverride.exa && exaKey != null) {
      return (await _exa(exaKey, query), 'Exa');
    }

    // Auto: preferred first, then the other on missing key/failure.
    if (wantTavily) {
      if (tavKey != null) {
        try {
          return (await _tavily(tavKey, query), 'Tavily');
        } catch (_) {
          /* fall through */
        }
      }
      if (exaKey != null) return (await _exa(exaKey, query), 'Exa');
      return (<SearchHit>[], null);
    } else {
      if (exaKey != null) {
        try {
          return (await _exa(exaKey, query), 'Exa');
        } catch (_) {
          /* fall through */
        }
      }
      if (tavKey != null)
        return (await _tavily(tavKey, query), 'Tavily' as String?);
      return (<SearchHit>[], null);
    }
  }

  Future<List<SearchHit>> _tavily(String key, SearchQuery q) => TavilyClient(
    apiKey: key,
  ).search(q.q, topic: q.intent == SearchIntent.news ? 'news' : 'general');

  Future<List<SearchHit>> _exa(String key, SearchQuery q) =>
      q.intent == SearchIntent.similar
      ? ExaClient(apiKey: key).similar(q.q)
      : ExaClient(apiKey: key).search(q.q);
}
