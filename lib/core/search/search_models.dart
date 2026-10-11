/// Search/research domain models — shared by the search providers, the
/// research pipeline, and the trace UI. URLs and titles only ever come from
/// real provider responses or our own fetches — never from model text.
library;

/// One search intent — drives provider choice in SearchRouter.
enum SearchIntent { news, factcheck, semantic, similar, extract }

/// A planned query the model asked for.
class SearchQuery {
  const SearchQuery({required this.q, this.intent = SearchIntent.semantic});
  final String q;
  final SearchIntent intent;
}

/// Fetch status for a source — only our own records set this.
enum HitStatus { unverified, verified, reachable, dead }

/// One real retrieved source. Rendered with favicon, breadcrumb, status.
class SearchHit {
  const SearchHit({
    required this.url,
    required this.title,
    required this.snippet,
    required this.provider,
    this.status = HitStatus.unverified,
    this.body,
  });

  final String url;
  final String title;
  final String snippet;

  /// Which search provider returned this ('Tavily' / 'Exa').
  final String provider;
  final HitStatus status;

  /// Extracted page text when Read step fetched it (untrusted content).
  final String? body;

  String get host => Uri.tryParse(url)?.host ?? url;
  String get favicon =>
      'https://www.google.com/s2/favicons?domain=$host&sz=64';

  /// "host › first path segment" breadcrumb.
  String get breadcrumb {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    final seg = u.pathSegments.isNotEmpty ? u.pathSegments.first : '';
    return seg.isEmpty ? host : '$host › $seg';
  }

  SearchHit copyWith({HitStatus? status, String? body}) => SearchHit(
        url: url,
        title: title,
        snippet: snippet,
        provider: provider,
        status: status ?? this.status,
        body: body ?? this.body,
      );
}

/// One line in the research trace tree the UI renders.
sealed class TraceEvent {
  const TraceEvent({required this.at});
  final DateTime at;
}

/// A step header: planning/searching/reading/writing.
class TraceStep extends TraceEvent {
  const TraceStep(
      {required super.at, required this.label, required this.kind});
  final String label;

  /// 'plan' | 'search' | 'read' | 'write' — icon pick in the UI.
  final String kind;
}

/// "Searching: <q>" row with provider tag.
class TraceQuery extends TraceEvent {
  const TraceQuery(
      {required super.at, required this.query, this.provider});
  final SearchQuery query;
  final String? provider;
}

/// One retrieved source row in the tree.
class TraceSource extends TraceEvent {
  const TraceSource({required super.at, required this.hit});
  final SearchHit hit;
}

/// The whole trace for one answer — rendered above it.
class ResearchTrace {
  final events = <TraceEvent>[];
  final startedAt = DateTime.now();
  DateTime? finishedAt;

  Duration get elapsed =>
      (finishedAt ?? DateTime.now()).difference(startedAt);

  List<SearchHit> get sources => [
        for (final e in events)
          if (e is TraceSource) e.hit,
      ];
}
