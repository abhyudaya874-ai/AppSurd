import 'package:dio/dio.dart';

/// A GitHub commit summarized for the verifier: message, files touched, and a
/// trimmed patch (≤6KB total so prompts stay small).
class CommitInfo {
  const CommitInfo({
    required this.url,
    required this.ok,
    this.message = '',
    this.files = const [],
    this.patch = '',
    this.error,
  });

  final String url;
  final bool ok;
  final String message;
  final List<String> files;
  final String patch;
  final String? error;
}

/// Fetches commit/PR evidence via the public GitHub REST API — unauthenticated
/// (rate-limited, fine for a demo) and read-only.
class GitHubClient {
  GitHubClient([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'Accept': 'application/vnd.github+json',
                'X-GitHub-Api-Version': '2022-11-28',
              },
            ));

  final Dio _dio;
  static const _patchCap = 6 * 1024;

  /// Parses `github.com/{owner}/{repo}/commit/{sha}` or `/pull/{n}` URLs.
  Future<CommitInfo> fetchCommit(String rawUrl) async {
    final commitRe =
        RegExp(r'github\.com/([^/]+)/([^/]+)/commit/([0-9a-fA-F]{6,40})');
    final pullRe =
        RegExp(r'github\.com/([^/]+)/([^/]+)/pull/(\d+)');
    final cm = commitRe.firstMatch(rawUrl);
    final pm = pullRe.firstMatch(rawUrl);
    if (cm == null && pm == null) {
      return CommitInfo(
          url: rawUrl, ok: false, error: 'Not a GitHub commit/PR URL');
    }
    try {
      if (cm != null) {
        return await _fetchCommit(cm[1]!, cm[2]!, cm[3]!, rawUrl);
      }
      return await _fetchPull(pm![1]!, pm[2]!, pm[3]!, rawUrl);
    } on DioException catch (e) {
      return CommitInfo(
        url: rawUrl,
        ok: false,
        error: 'HTTP ${e.response?.statusCode ?? 'timeout'}',
      );
    }
  }

  Future<CommitInfo> _fetchCommit(
      String owner, String repo, String sha, String url) async {
    final res = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$owner/$repo/commits/$sha');
    final data = res.data;
    if (data == null) return CommitInfo(url: url, ok: false);
    final files = <String>[];
    final patch = StringBuffer();
    for (final f in (data['files'] as List? ?? const [])) {
      if (f is Map) {
        files.add(f['filename'] as String? ?? '');
        final p = f['patch'] as String?;
        if (p != null && patch.length < _patchCap) {
          patch.writeln('--- ${f['filename']}');
          patch.writeln(p);
        }
      }
    }
    return CommitInfo(
      url: url,
      ok: true,
      message: ((data['commit'] as Map?)?['message'] as String?) ?? '',
      files: files,
      patch: patch.toString().length > _patchCap
          ? patch.toString().substring(0, _patchCap)
          : patch.toString(),
    );
  }

  Future<CommitInfo> _fetchPull(
      String owner, String repo, String num, String url) async {
    final pr = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$owner/$repo/pulls/$num');
    final files = await _dio.get<List<dynamic>>(
        'https://api.github.com/repos/$owner/$repo/pulls/$num/files?per_page=30');
    final names = <String>[];
    final patch = StringBuffer();
    for (final f in files.data ?? const []) {
      if (f is Map) {
        names.add(f['filename'] as String? ?? '');
        final p = f['patch'] as String?;
        if (p != null && patch.length < _patchCap) {
          patch.writeln('--- ${f['filename']}');
          patch.writeln(p);
        }
      }
    }
    return CommitInfo(
      url: url,
      ok: true,
      message: '${pr.data?['title'] ?? ''}\n${pr.data?['body'] ?? ''}',
      files: names,
      patch: patch.toString().length > _patchCap
          ? patch.toString().substring(0, _patchCap)
          : patch.toString(),
    );
  }
}
