import 'dart:math';

/// Local fallback roasts — passive-aggressive, funny, aimed at the EVIDENCE
/// (never the person), zero profanity. Used when the model call fails or
/// returns no roast, so the demo never dead-ends offline.
abstract final class RoastBank {
  static const _roasts = [
    'That evidence has the energy of a group project where "everyone helped".',
    'I\'ve seen stronger proof in a horoscope.',
    'Submitting this was certainly a choice.',
    'The confidence. The audacity. The complete lack of supporting detail.',
    'Ah yes, the classic "trust me" artifact. The Smithsonian wants it back.',
    'This evidence is doing a lot of work. Emotionally, mostly.',
    'I ran this past my fact-checker. My fact-checker is a goldfish, and it was unimpressed.',
    'Somewhere, a very patient lawyer is shaking their head.',
    'If effort were a currency, this would be store credit at a closed store.',
    'This is the productivity equivalent of "the dog ate my homework", except the dog also seems unconvinced.',
    'Lovely story. Now — any chance of a version with evidence in it?',
    'I\'m not saying it\'s weak, but a strong breeze could cross-examine it.',
    'The receipts are giving… wallpaper. Decorative, not load-bearing.',
    'A masterpiece of the genre "things that technically count as submission".',
    'I wanted to believe. The evidence did not let me.',
  ];

  static int _last = -1;

  /// Random roast, never repeating the previous one back-to-back.
  static String pick() {
    var i = Random().nextInt(_roasts.length);
    while (i == _last && _roasts.length > 1) {
      i = Random().nextInt(_roasts.length);
    }
    _last = i;
    return _roasts[i];
  }
}
