// READ THIS FIRST — we fetch, not the model. 8s timeout, 200KB cap,
// redirects followed, tags stripped, ≤4 concurrent. Sources of truth.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

/// What we learned by fetching a link ourselves. `ok` = 2xx. `textExtract` is
/// the page's readable text (capped) — claims are cross-checked against it.
class LinkCheck {
  const LinkCheck({
    required this.uri,
    required this.ok,
    this.statusCode,
    this.finalUrl,
    this.title,
    this.description,
    this.textExtract = '',
    this.error,
  });

  final Uri uri;
  final bool ok;
  final int? statusCode;
  final String? finalUrl;
  final String? title;
  final String? description;
  final String textExtract;
  final String? error;
}

/// Fetches URLs ourselves — never trust the model's word that a link works.
/// 8s timeout, redirects followed, body capped at ~200KB, tags stripped.
/// Concurrency-limited to 4 in-flight fetches.
class LinkVerifier {
  LinkVerifier([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              followRedirects: true,
              maxRedirects: 5,
              headers: {
                // Some sites 403 plain-Dio; a plain browser UA is honest here.
                'User-Agent': 'Mozilla/5.0 (compatible; ReceiptsBot/1.0)',
                'Accept': 'text/html,application/xhtml+xml,*/*',
              },
            ),
          );

  final Dio _dio;
  static const _maxBytes = 200 * 1024;
  static int _inFlight = 0;
  static final _queue = <Completer<void>>[];

  /// Acquires one of 4 fetch slots.
  static Future<void> _acquire() async {
    if (_inFlight < 4) {
      _inFlight++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
    _inFlight++;
  }

  static void _release() {
    _inFlight--;
    if (_queue.isNotEmpty) _queue.removeAt(0).complete();
  }

  Future<LinkCheck> verify(Uri uri) async {
    await _acquire();
    try {
      final res = await _dio.getUri<List<int>>(
        uri,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (got, total) {
          // Dio can't abort mid-body natively; we cap on read after.
        },
      );
      final ok = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
      final bytes = res.data ?? const <int>[];
      final capped = bytes.length > _maxBytes
          ? bytes.sublist(0, _maxBytes)
          : bytes;
      final body = String.fromCharCodes(capped, 0, capped.length);
      final parsed = ok ? _parseHtml(body) : const _ParsedPage();
      return LinkCheck(
        uri: uri,
        ok: ok,
        statusCode: res.statusCode,
        finalUrl: res.realUri.toString(),
        title: parsed.title,
        description: parsed.description,
        textExtract: parsed.text,
      );
    } on DioException catch (e) {
      return LinkCheck(
        uri: uri,
        ok: false,
        statusCode: e.response?.statusCode,
        error: e.type.name,
      );
    } finally {
      _release();
    }
  }

  /// Strips a fetched page to title + meta description + visible text.
  _ParsedPage _parseHtml(String body) {
    try {
      final doc = html_parser.parse(body);
      final title = doc.querySelector('title')?.text.trim();
      final meta = doc
          .querySelector(
            'meta[name="description"],meta[property="og:description"]',
          )
          ?.attributes['content']
          ?.trim();
      // Drop non-visible noise before collecting text.
      for (final el in doc.querySelectorAll(
        'script,style,noscript,svg,nav,footer',
      )) {
        el.remove();
      }
      final text = _visibleText(doc.body)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return _ParsedPage(
        title: title?.isEmpty ?? true ? null : title,
        description: meta?.isEmpty ?? true ? null : meta,
        text: text.length > 12000 ? text.substring(0, 12000) : text,
      );
    } catch (_) {
      return const _ParsedPage();
    }
  }

  String _visibleText(dom.Element? el) {
    if (el == null) return '';
    final buf = StringBuffer();
    void walk(dom.Node n) {
      if (n is dom.Text) buf.write('${n.text} ');
      if (n is dom.Element) {
        for (final c in n.nodes) {
          walk(c);
        }
      }
    }

    walk(el);
    return buf.toString();
  }
}

class _ParsedPage {
  const _ParsedPage({this.title, this.description, this.text = ''});
  final String? title;
  final String? description;
  final String text;
}
