import 'package:dio/dio.dart';

import 'search_models.dart';

/// Tavily API (docs.tavily.com): POST /search with {api_key, query,
/// max_results, topic} and POST /extract with {api_key, urls}. Bearer-less:
/// the key rides in the JSON body (their documented format).
class TavilyClient {
  TavilyClient({required this.apiKey});
  final String apiKey;

  final _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.tavily.com',
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  /// Returns up to [maxResults] hits for [query].
  Future<List<SearchHit>> search(
    String query, {
    int maxResults = 5,
    String? topic,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/search',
      data: {
        'api_key': apiKey,
        'query': query,
        'max_results': maxResults,
        if (topic != null) 'topic': topic,
      },
    );
    final results = (res.data?['results'] as List? ?? const []);
    return [
      for (final r in results)
        if (r is Map)
          SearchHit(
            url: r['url'] as String? ?? '',
            title: r['title'] as String? ?? '',
            snippet: r['content'] as String? ?? '',
            provider: 'Tavily',
          ),
    ];
  }

  /// Fetches clean page text for up to a few URLs.
  Future<Map<String, String>> extract(List<String> urls) async {
    if (urls.isEmpty) return const {};
    final res = await _dio.post<Map<String, dynamic>>(
      '/extract',
      data: {'api_key': apiKey, 'urls': urls.take(4).toList()},
    );
    final results = (res.data?['results'] as List? ?? const []);
    return {
      for (final r in results)
        if (r is Map)
          r['url'] as String? ?? '': (r['raw_content'] as String? ?? ''),
    }..remove('');
  }

  /// "Test key" ping — a tiny query just to validate credentials.
  Future<bool> ping() async {
    try {
      await search('receipts ping', maxResults: 1);
      return true;
    } on DioException {
      return false;
    }
  }
}
