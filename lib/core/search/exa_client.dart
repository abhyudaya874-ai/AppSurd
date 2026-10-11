import 'package:dio/dio.dart';

import 'search_models.dart';

/// Exa API (docs.exa.ai): POST /search with {query, numResults, contents}
/// and POST /findSimilar with {url}. Key rides as `x-api-key` header.
class ExaClient {
  ExaClient({required this.apiKey});
  final String apiKey;

  late final _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.exa.ai',
      headers: {'x-api-key': apiKey},
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  Future<List<SearchHit>> search(String query, {int numResults = 5}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/search',
      data: {
        'query': query,
        'numResults': numResults,
        'contents': {
          'text': {'maxCharacters': 400},
        },
      },
    );
    final results = (res.data?['results'] as List? ?? const []);
    return [
      for (final r in results)
        if (r is Map)
          SearchHit(
            url: r['url'] as String? ?? '',
            title: r['title'] as String? ?? '',
            snippet: r['text'] as String? ?? '',
            provider: 'Exa',
          ),
    ];
  }

  /// find-similar: pages like the given URL — used by the lookalike check.
  Future<List<SearchHit>> similar(String url, {int numResults = 3}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/findSimilar',
      data: {
        'url': url,
        'numResults': numResults,
        'contents': {
          'text': {'maxCharacters': 200},
        },
      },
    );
    final results = (res.data?['results'] as List? ?? const []);
    return [
      for (final r in results)
        if (r is Map)
          SearchHit(
            url: r['url'] as String? ?? '',
            title: r['title'] as String? ?? '',
            snippet: r['text'] as String? ?? '',
            provider: 'Exa',
          ),
    ];
  }

  Future<bool> ping() async {
    try {
      await search('receipts ping', numResults: 1);
      return true;
    } on DioException {
      return false;
    }
  }
}
