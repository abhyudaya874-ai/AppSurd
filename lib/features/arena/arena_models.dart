import '../../core/ai/model_catalog.dart';
import '../verification/verdict_model.dart';

/// Strictness detents on the arena slider — each sets the pass threshold the
/// code applies to the consensus verdict and one line in the judge prompt.
enum Strictness {
  lenient(0.55, 'Be charitable — pass reasonable evidence.'),
  fair(0.7, 'Judge fairly.'),
  strict(0.8, 'Be strict — only airtight evidence passes.'),
  brutal(0.9, 'Be brutal — doubt everything not nailed down.');

  const Strictness(this.passThreshold, this.promptLine);
  final double passThreshold;
  final String promptLine;
}

/// One judge's ruling (or its failure — DNF card, never an exception).
class JudgeResult {
  const JudgeResult({
    required this.model,
    required this.latencyMs,
    this.verdict,
    this.error,
  });

  final ModelSpec model;
  final int latencyMs;

  /// Null verdict = DNF; [error] carries the short reason.
  final Verdict? verdict;
  final String? error;

  bool get finished => verdict != null;
}

/// Aggregated arena outcome — computed in code, never delegated to a model.
class ArenaOutcome {
  const ArenaOutcome({
    required this.results,
    required this.consensus,
    required this.agreement,
    required this.dissenters,
    required this.strictest,
    required this.consensusVerdict,
  });

  final List<JudgeResult> results;

  /// Winning verdict kind after confidence-weighted vote.
  final VerdictKind consensus;

  /// Share of finished judges that matched the consensus (0–1).
  final double agreement;
  final List<JudgeResult> dissenters;

  /// The judge with the harshest vote (highest confidence on ties) — its
  /// roast + challenge are the ones the card shows.
  final JudgeResult? strictest;

  /// The winning judge's full verdict (what gets applied to the task).
  final Verdict consensusVerdict;
}
