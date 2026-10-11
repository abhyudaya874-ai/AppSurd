import '../../core/search/search_models.dart';
import '../research/research_pipeline.dart';

/// Folds PipelineEvents into a ResearchTrace's event list (kept separate so
/// the pipeline stays UI-free).
void applyTraceEvent(ResearchTrace trace, PipelineEvent e) {
  final now = DateTime.now();
  switch (e) {
    case PipelineStep():
      trace.events.add(TraceStep(at: now, label: e.label, kind: e.kind));
    case PipelineQuery():
      trace.events.add(TraceQuery(at: now, query: e.q));
    case PipelineQueryDone():
      // Attach provider to the last query row.
      final i = trace.events.lastIndexWhere((x) => x is TraceQuery);
      if (i >= 0) {
        final q = (trace.events[i] as TraceQuery).query;
        trace.events[i] = TraceQuery(at: now, query: q, provider: e.provider);
      }
    case PipelineSource():
      trace.events.add(TraceSource(at: now, hit: e.hit));
    case PipelineDone() || PipelineNoSearch():
      trace.finishedAt = now;
  }
}
