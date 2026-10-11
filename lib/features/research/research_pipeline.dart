import 'dart:convert';

import '../../core/ai/model_catalog.dart';
import '../../core/ai/model_router.dart';
import '../../core/ai/openai_compat_client.dart';
import '../../core/ai/prompts.dart';
import '../../core/search/search_models.dart';
import '../../core/search/search_router.dart';
import '../../core/net/link_verifier.dart';

/// The agentic pipeline — Plan ⇒ Search ⇒ Read ⇒ Synthesize, orchestrated in
/// code so ANY model can drive it (no tool-calling required). Emits
/// PipelineEvents that the UI folds into a ResearchTrace.
class ResearchPipeline {
  const ResearchPipeline();

  Stream<PipelineEvent> run({
    required String question,
    required ModelRouter router,
    required RoutePlan plan,
    required Map<AiProvider, String> aiKeys,
    required Map<String, String> searchKeys,
    SearchOverride override = SearchOverride.auto,
    AgenticMode mode = AgenticMode.search,
  }) async* {
    if (mode == AgenticMode.off || plan.candidates.isEmpty) {
      yield const PipelineEvent.noSearch();
      return;
    }

    // ---- 1. Plan: model decides what to look up (JSON, ≤3 queries) ----
    yield PipelineEvent.step('Planning', 'plan');
    List<SearchQuery> queries = [];
    try {
      final outcome = await router.execute<String>(
        plan,
        (client, spec) => client.complete(
          model: spec.id,
          jsonMode: true,
          maxTokens: 300,
          messages: [
            const ChatMessage(role: 'system', content: planSystem),
            ChatMessage.text('user', question),
          ],
        ),
        aiKeys,
      );
      final block = _json(outcome.value);
      queries = [
        for (final q in (block?['queries'] as List? ?? const []).take(3))
          if (q is Map)
            SearchQuery(
              q: q['q'] as String? ?? '',
              intent: SearchIntent.values.firstWhere(
                (i) => i.name == q['intent'],
                orElse: () => SearchIntent.semantic,
              ),
            ),
      ];
      if (block?['needs_search'] == false) queries = [];
    } catch (_) {
      queries = [SearchQuery(q: question, intent: SearchIntent.semantic)];
    }

    if (queries.isEmpty) {
      yield const PipelineEvent.noSearch();
      return;
    }

    // ---- 2. Search concurrently through the router ----
    final searchRouter = SearchRouter(searchKeys);
    final seen = <String>{};
    final allHits = <SearchHit>[];
    for (final q in queries) {
      yield PipelineEvent.query(q);
      final (hits, provider) =
          await searchRouter.run(q, override_: override);
      yield PipelineEvent.queryDone(q, provider);
      for (final h in hits.take(5)) {
        if (seen.add(h.url)) allHits.add(h);
      }
    }

    // ---- 3. Read: verify top pages with our own LinkVerifier ----
    if (allHits.isNotEmpty) {
      yield PipelineEvent.step('Reading sources', 'read');
      final verifier = LinkVerifier();
      final verified = <SearchHit>[];
      for (final h in allHits.take(8)) {
        try {
          final check = await verifier.verify(Uri.parse(h.url));
          final text = check.textExtract;
          verified.add(h.copyWith(
            status: check.ok ? HitStatus.verified : HitStatus.dead,
            body: check.ok
                ? text.substring(0, text.length.clamp(0, 1200))
                : null,
          ));
        } catch (_) {
          verified.add(h.copyWith(status: HitStatus.unverified));
        }
      }
      allHits
        ..clear()
        ..addAll(verified);
      for (final h in allHits) {
        yield PipelineEvent.source(h);
      }
    }

    yield PipelineEvent.done(allHits);
  }

  /// Strips citations that don't map to a retrieved source, and raw URLs the
  /// model wrote that aren't ours — "real links only", enforced in code.
  static String scrubAnswer(String text, List<SearchHit> sources) {
    var out = text;
    out = out.replaceAllMapped(RegExp(r'\[(\d+)\]'), (m) {
      final n = int.tryParse(m.group(1)!) ?? -1;
      return (n >= 1 && n <= sources.length) ? m.group(0)! : '';
    });
    final ours = sources.map((s) => s.url).toSet();
    out = out.replaceAllMapped(
      RegExp(r'https?://\S+'),
      (m) => ours.contains(m.group(0)!.replaceAll(RegExp(r'[).,;]+$'), ''))
          ? m.group(0)!
          : '',
    );
    return out;
  }

  static Map<String, dynamic>? _json(String? raw) {
    if (raw == null) return null;
    final i = raw.indexOf('{');
    final j = raw.lastIndexOf('}');
    if (i < 0 || j <= i) return null;
    try {
      return jsonDecode(raw.substring(i, j + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// The numbered source list passed to the synthesis prompt.
  static String sourceBlock(List<SearchHit> sources) {
    final b = StringBuffer('SOURCES:\n');
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      b.writeln('[${i + 1}] ${s.title} — ${s.host}');
      final body = (s.body ?? s.snippet).trim();
      if (body.isNotEmpty) b.writeln(body.substring(0, body.length.clamp(0, 600)));
      b.writeln();
    }
    return b.toString();
  }
}

sealed class PipelineEvent {
  const PipelineEvent();

  const factory PipelineEvent.step(String label, String kind) = PipelineStep;
  const factory PipelineEvent.query(SearchQuery q) = PipelineQuery;
  const factory PipelineEvent.queryDone(SearchQuery q, String? provider) =
      PipelineQueryDone;
  const factory PipelineEvent.source(SearchHit hit) = PipelineSource;
  const factory PipelineEvent.done(List<SearchHit> sources) = PipelineDone;
  const factory PipelineEvent.noSearch() = PipelineNoSearch;
}

class PipelineStep extends PipelineEvent {
  const PipelineStep(this.label, this.kind);
  final String label;
  final String kind;
}

class PipelineQuery extends PipelineEvent {
  const PipelineQuery(this.q);
  final SearchQuery q;
}

class PipelineQueryDone extends PipelineEvent {
  const PipelineQueryDone(this.q, this.provider);
  final SearchQuery q;
  final String? provider;
}

class PipelineSource extends PipelineEvent {
  const PipelineSource(this.hit);
  final SearchHit hit;
}

class PipelineDone extends PipelineEvent {
  const PipelineDone(this.sources);
  final List<SearchHit> sources;
}

class PipelineNoSearch extends PipelineEvent {
  const PipelineNoSearch();
}
