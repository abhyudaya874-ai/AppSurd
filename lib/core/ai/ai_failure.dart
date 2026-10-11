/// Typed failure for every provider/network error. The UI maps these to
/// friendly in-character messages — users never see raw exceptions.
sealed class AiFailure implements Exception {
  const AiFailure(this.message);

  /// Safe, key-free description of what went wrong.
  final String message;

  @override
  String toString() => 'AiFailure($runtimeType): $message';
}

/// HTTP 401/403 — bad or missing key.
final class AuthFailure extends AiFailure {
  const AuthFailure([super.message = 'That API key was rejected.']);
}

/// HTTP 429 — provider rate limit; triggers router fallback.
final class RateLimitFailure extends AiFailure {
  const RateLimitFailure([super.message = 'Provider rate limit hit.']);
}

/// Timeout / DNS / socket errors — triggers router fallback.
final class NetworkFailure extends AiFailure {
  const NetworkFailure([super.message = 'Network request failed.']);
}

/// HTTP 5xx or a response that isn't shaped like a chat completion.
final class BadResponseFailure extends AiFailure {
  const BadResponseFailure([super.message = 'Provider returned a bad response.']);
}
