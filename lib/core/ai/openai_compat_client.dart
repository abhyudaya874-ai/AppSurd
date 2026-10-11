// READ THIS FIRST — the only network voice in the app. Three providers,
// one OpenAI-compatible /chat/completions shape; stream() parses SSE.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'ai_failure.dart';

/// One chat-message shape shared by all three providers
/// (OpenAI-compatible /chat/completions).
class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  /// 'system' | 'user' | 'assistant'
  final String role;

  /// Either a plain string or a list of content parts (for vision requests).
  final Object content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  /// Convenience constructor for text-only messages.
  factory ChatMessage.text(String role, String text) =>
      ChatMessage(role: role, content: text);
}

/// A single client class for every provider — Groq, NVIDIA NIM and OpenRouter
/// all expose the OpenAI-compatible /chat/completions and /models endpoints,
/// so the only differences are the base URL, the key, and extra headers.
class OpenAiCompatClient {
  OpenAiCompatClient({
    required this.baseUrl,
    required this.apiKey,
    this.extraHeaders = const {},
    Dio? dio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 30),
             ),
           );

  final String baseUrl;
  final String apiKey;
  final Map<String, String> extraHeaders;
  final Dio _dio;

  Options _options({ResponseType? responseType, Duration? receiveTimeout}) {
    return Options(
      responseType: responseType,
      receiveTimeout: receiveTimeout,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        ...extraHeaders,
      },
    );
  }

  /// GET /models — used at boot and by "Test key" to validate credentials and
  /// prune the catalog of models that no longer exist.
  Future<Set<String>> listModelIds() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/models',
        options: _options(),
      );
      final data = res.data?['data'];
      if (data is! List) throw const BadResponseFailure('Missing model list.');
      return {
        for (final m in data)
          if (m is Map && m['id'] is String) m['id'] as String,
      };
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Non-streaming chat completion — used for the JSON verdict contract.
  /// Returns the assistant message content as a string.
  Future<String> complete({
    required String model,
    required List<ChatMessage> messages,
    bool jsonMode = false,
    double temperature = 0.4,
    int maxTokens = 1024,
    String? reasoningEffort,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': [for (final m in messages) m.toJson()],
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
      if (jsonMode) 'response_format': {'type': 'json_object'},
      'reasoning_effort': ?reasoningEffort,
    };
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/chat/completions',
        data: body,
        options: _options(),
      );
      final choices = res.data?['choices'];
      if (choices is! List || choices.isEmpty) {
        throw const BadResponseFailure('Empty choices in completion.');
      }
      final content = (choices.first as Map)['message']?['content'];
      if (content is! String) {
        throw const BadResponseFailure('Missing message content.');
      }
      return content;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// SSE token stream — yields each delta content string as it arrives and
  /// completes on the `[DONE]` sentinel. Used for streaming verdict text.
  Stream<String> stream({
    required String model,
    required List<ChatMessage> messages,
    double temperature = 0.6,
    int maxTokens = 1024,
  }) async* {
    await for (final c in streamRich(
      model: model,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
    )) {
      if (c.text.isNotEmpty) yield c.text;
    }
  }

  /// Rich stream — separates answer text from reasoning deltas
  /// (`reasoning`/`reasoning_content` fields, or inline <think> tags).
  /// A model with no reasoning simply yields text chunks.
  Stream<StreamChunk> streamRich({
    required String model,
    required List<ChatMessage> messages,
    double temperature = 0.6,
    int maxTokens = 1024,
  }) async* {
    final body = {
      'model': model,
      'messages': [for (final m in messages) m.toJson()],
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': true,
    };
    final Response<ResponseBody> res;
    try {
      res = await _dio.post<ResponseBody>(
        '$baseUrl/chat/completions',
        data: body,
        options: _options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }

    final bodyStream = res.data?.stream;
    if (bodyStream == null) throw const BadResponseFailure('No stream body.');

    // SSE frames are separated by blank lines; buffer partial frames between
    // chunk boundaries so a split "data:" line still parses.
    var _inThink = false;
    final buffer = StringBuffer();
    await for (final chunk in bodyStream) {
      buffer.write(utf8.decode(chunk, allowMalformed: true));
      final text = buffer.toString();
      final lastBreak = text.lastIndexOf('\n');
      if (lastBreak < 0) continue;
      final completePart = text.substring(0, lastBreak);
      buffer
        ..clear()
        ..write(text.substring(lastBreak + 1));
      for (final line in completePart.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') return;
        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final choices = json['choices'];
          if (choices is List && choices.isNotEmpty) {
            final delta = (choices.first as Map)['delta'];
            if (delta is Map) {
              final reasoning =
                  delta['reasoning'] ??
                  delta['reasoning_content'] ??
                  delta['thinking'];
              final content = delta['content'];
              if (reasoning is String && reasoning.isNotEmpty) {
                yield StreamChunk(reasoning: reasoning);
              }
              if (content is String && content.isNotEmpty) {
                // Inline <think>…</think> inside content (DeepSeek-style):
                // route it to the reasoning channel, honestly labelled.
                var rest = content;
                while (rest.isNotEmpty) {
                  if (_inThink) {
                    final close = rest.indexOf('</think>');
                    if (close < 0) {
                      yield StreamChunk(reasoning: rest);
                      rest = '';
                    } else {
                      yield StreamChunk(reasoning: rest.substring(0, close));
                      rest = rest.substring(close + 8);
                      _inThink = false;
                    }
                  } else {
                    final open = rest.indexOf('<think>');
                    if (open < 0) {
                      yield StreamChunk(text: rest);
                      rest = '';
                    } else {
                      if (open > 0) {
                        yield StreamChunk(text: rest.substring(0, open));
                      }
                      rest = rest.substring(open + 7);
                      _inThink = true;
                    }
                  }
                }
              }
            }
          }
        } on FormatException {
          // A malformed SSE frame is skipped, not fatal.
        }
      }
    }
  }

  /// Maps transport errors onto the typed failure taxonomy used by the router
  /// and the UI. Keys are never included in messages.
  AiFailure _mapError(DioException e) {
    final code = e.response?.statusCode ?? 0;
    if (code == 401 || code == 403) return const AuthFailure();
    if (code == 429) return const RateLimitFailure();
    if (code >= 500) return const BadResponseFailure('Provider server error.');
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const NetworkFailure();
    }
    return BadResponseFailure('HTTP $code');
  }
}

/// One streamed delta — [text] for answer tokens, [reasoning] for visible
/// thinking deltas (`reasoning`/`reasoning_content`/`thinking` fields or
/// inline <think> tags, whichever the provider emits).
class StreamChunk {
  const StreamChunk({this.text = '', this.reasoning = ''});
  final String text;
  final String reasoning;
}
