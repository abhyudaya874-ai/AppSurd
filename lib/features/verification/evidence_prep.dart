import 'dart:convert';
import 'dart:io';

import '../../core/net/github_client.dart';
import '../../core/net/link_verifier.dart';
import '../tasks/task_model.dart';

/// Prepared evidence — everything a judge needs. Fetching happens ONCE here
/// and the result is shared across judges (arena) or a single verifier,
/// keeping sources identical and rate limits low.
class PreparedEvidence {
  const PreparedEvidence({
    required this.evidenceText,
    required this.needsVision,
    required this.fetchFailed,
    this.imageB64,
    this.checks = const [],
    this.commit,
  });

  final String evidenceText;
  final bool needsVision;
  final bool fetchFailed;
  final String? imageB64;
  final List<LinkCheck> checks;
  final CommitInfo? commit;
}

/// Reads an [EvidenceAttempt] into judge-ready form: fetches URLs, pulls
/// commit data from the GitHub API, base64s screenshots (≤1280px), passes
/// text through. `fetchFailed` = dead evidence → forced fail downstream.
Future<PreparedEvidence> prepareEvidence(EvidenceAttempt attempt) async {
  final checks = <LinkCheck>[];
  CommitInfo? commit;
  String evidenceText;
  var needsVision = false;
  String? imageB64;
  var fetchFailed = false;

  switch (attempt.type) {
    case EvidenceType.url:
      final uri = Uri.tryParse(attempt.payload);
      if (uri == null) {
        evidenceText = 'Invalid URL: ${attempt.payload}';
        fetchFailed = true;
        break;
      }
      final check = await LinkVerifier().verify(uri);
      checks.add(check);
      fetchFailed = !check.ok;
      evidenceText = check.ok
          ? 'Fetched page — title: ${check.title ?? 'none'}\n'
              'description: ${check.description ?? 'none'}\n'
              'content: ${check.textExtract.substring(0, check.textExtract.length > 8000 ? 8000 : check.textExtract.length)}'
          : 'The URL could not be fetched (HTTP ${check.statusCode ?? 'error'}).';
    case EvidenceType.commit:
      commit = await GitHubClient().fetchCommit(attempt.payload);
      fetchFailed = !commit.ok;
      evidenceText = commit.ok
          ? 'GitHub commit — message: ${commit.message}\n'
              'files changed: ${commit.files.join(', ')}\n'
              'patch:\n${commit.patch}'
          : 'The commit could not be fetched (${commit.error}).';
    case EvidenceType.screenshot:
      needsVision = true;
      try {
        final bytes = await File(attempt.payload).readAsBytes();
        imageB64 = base64Encode(bytes);
        evidenceText =
            '[Screenshot attached — judge whether it shows the task done]';
      } catch (_) {
        evidenceText = 'Screenshot file could not be read.';
        fetchFailed = true;
      }
    case EvidenceType.text:
      evidenceText = attempt.payload;
  }

  return PreparedEvidence(
    evidenceText: evidenceText,
    needsVision: needsVision,
    fetchFailed: fetchFailed,
    imageB64: imageB64,
    checks: checks,
    commit: commit,
  );
}

/// Judge-visible source texts, in source order — index matches the strip.
List<String> evidenceSourceTexts(PreparedEvidence p) => [
      for (final c in p.checks) c.textExtract,
      if (p.commit != null) p.commit!.patch,
    ];
