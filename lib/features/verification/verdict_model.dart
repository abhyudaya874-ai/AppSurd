/// The strict-JSON contract the verifier model must return. Parsed
/// defensively — models sometimes wrap JSON in prose or code fences, so we
/// extract the first balanced {...} block before decoding.
library;

// READ THIS FIRST — the strict-JSON contract + defensive parser. The
// confidence floor (pass needs >=0.7) is enforced HERE, not in a prompt.
import 'dart:convert';

enum VerdictKind { pass, partial, fail }

/// One rubric line the model checked ("mentions the deliverable", etc).
class VerdictCheck {
  const VerdictCheck({required this.label, required this.ok});
  final String label;
  final bool ok;

  factory VerdictCheck.fromJson(Map<String, dynamic> j) => VerdictCheck(
        label: j['label'] as String? ?? '',
        ok: j['ok'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'label': label, 'ok': ok};
}

/// A claim the model made, pointing at a fetched source by index.
class VerdictClaim {
  const VerdictClaim({required this.text, required this.sourceIndex});
  final String text;
  final int sourceIndex;

  factory VerdictClaim.fromJson(Map<String, dynamic> j) => VerdictClaim(
        text: j['text'] as String? ?? '',
        sourceIndex: (j['source_index'] as num?)?.toInt() ?? -1,
      );

  Map<String, dynamic> toJson() =>
      {'text': text, 'source_index': sourceIndex};
}

/// Accountability challenge issued on partial/fail.
class ChallengeDef {
  const ChallengeDef({
    required this.title,
    required this.instructions,
    required this.seconds,
    required this.kind,
  });

  final String title;
  final String instructions;
  final int seconds;

  /// 'retype' | 'quiz' | 'reupload'
  final String kind;

  factory ChallengeDef.fromJson(Map<String, dynamic> j) => ChallengeDef(
        title: j['title'] as String? ?? 'Prove it',
        instructions: j['instructions'] as String? ?? '',
        seconds: (j['seconds'] as num?)?.toInt() ?? 60,
        kind: j['kind'] as String? ?? 'retype',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'instructions': instructions,
        'seconds': seconds,
        'kind': kind,
      };
}

/// The parsed verdict — what the whole verification UI renders from.
class Verdict {
  const Verdict({
    required this.kind,
    required this.confidence,
    required this.summary,
    required this.checks,
    required this.claims,
    this.roast,
    this.challenge,
  });

  final VerdictKind kind;
  final double confidence;
  final String summary;
  final List<VerdictCheck> checks;
  final List<VerdictClaim> claims;
  final String? roast;
  final ChallengeDef? challenge;

  Verdict copyWith({
    VerdictKind? kind,
    double? confidence,
    String? summary,
    List<VerdictCheck>? checks,
    List<VerdictClaim>? claims,
    String? roast,
    ChallengeDef? challenge,
  }) {
    return Verdict(
      kind: kind ?? this.kind,
      confidence: confidence ?? this.confidence,
      summary: summary ?? this.summary,
      checks: checks ?? this.checks,
      claims: claims ?? this.claims,
      roast: roast ?? this.roast,
      challenge: challenge ?? this.challenge,
    );
  }

  Map<String, dynamic> toJson() => {
        'verdict': kind.name,
        'confidence': confidence,
        'summary': summary,
        'checks': [for (final c in checks) c.toJson()],
        'claims': [for (final c in claims) c.toJson()],
        'roast': roast,
        'challenge': challenge?.toJson(),
      };

  /// Defensive parse — never throws; returns a safe "partial-ish" fallback.
  factory Verdict.fromJson(Map<String, dynamic> j) {
    return Verdict(
      kind: switch ((j['verdict'] as String? ?? '').toLowerCase()) {
        'pass' => VerdictKind.pass,
        'fail' => VerdictKind.fail,
        _ => VerdictKind.partial,
      },
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      summary: j['summary'] as String? ?? '',
      checks: [
        for (final c in (j['checks'] as List? ?? const []))
          if (c is Map) VerdictCheck.fromJson(c.cast<String, dynamic>()),
      ],
      claims: [
        for (final c in (j['claims'] as List? ?? const []))
          if (c is Map) VerdictClaim.fromJson(c.cast<String, dynamic>()),
      ],
      roast: j['roast'] as String?,
      challenge: j['challenge'] is Map
          ? ChallengeDef.fromJson(
              (j['challenge'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  /// Extract the first balanced {...} JSON object from arbitrary model text.
  /// Returns null when no balanced object exists.
  static String? extractJsonBlock(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\' && inString) {
        escaped = true;
        continue;
      }
      if (ch == '"') inString = !inString;
      if (inString) continue;
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  /// Full defensive pipeline: find a JSON block → decode → normalize → apply
  /// code-side rules (confidence < 0.7 downgrades pass to partial).
  static Verdict parse(String raw) {
    final block = extractJsonBlock(raw);
    if (block == null) {
      return const Verdict(
        kind: VerdictKind.partial,
        confidence: 0,
        summary: 'The verifier returned something unreadable.',
        checks: [],
        claims: [],
      );
    }
    try {
      final json = jsonDecode(block) as Map<String, dynamic>;
      var v = Verdict.fromJson(json);
      // The pass threshold is enforced in code, not trusted to the model.
      if (v.kind == VerdictKind.pass && v.confidence < 0.7) {
        v = Verdict(
          kind: VerdictKind.partial,
          confidence: v.confidence,
          summary: v.summary,
          checks: v.checks,
          claims: v.claims,
          roast: v.roast,
          challenge: v.challenge,
        );
      }
      return v;
    } on FormatException {
      return const Verdict(
        kind: VerdictKind.partial,
        confidence: 0,
        summary: 'The verifier returned malformed JSON.',
        checks: [],
        claims: [],
      );
    }
  }
}
