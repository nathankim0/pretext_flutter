import 'package:characters/characters.dart';

import 'types.dart';

// ---------------------------------------------------------------------------
// Exported data types
// ---------------------------------------------------------------------------

/// A single segmentation piece produced during word-boundary splitting.
class _SegmentationPiece {
  const _SegmentationPiece({
    required this.text,
    required this.isWordLike,
    required this.kind,
    required this.start,
  });

  final String text;
  final bool isWordLike;
  final SegmentBreakKind kind;
  final int start;
}

/// Flat parallel arrays describing a merged segmentation of a string.
class MergedSegmentation {
  MergedSegmentation({
    required this.len,
    required this.texts,
    required this.isWordLike,
    required this.kinds,
    required this.starts,
  });

  int len;
  List<String> texts;
  List<bool> isWordLike;
  List<SegmentBreakKind> kinds;
  List<int> starts;
}

/// Hard-break chunk boundaries within a segmentation.
class AnalysisChunk {
  const AnalysisChunk({
    required this.startSegmentIndex,
    required this.endSegmentIndex,
    required this.consumedEndSegmentIndex,
  });

  final int startSegmentIndex;
  final int endSegmentIndex;
  final int consumedEndSegmentIndex;
}

/// Complete result of [analyzeText]: normalized text, merged segments, and
/// hard-break chunks.
class TextAnalysis {
  const TextAnalysis({
    required this.normalized,
    required this.chunks,
    required this.len,
    required this.texts,
    required this.isWordLike,
    required this.kinds,
    required this.starts,
  });

  final String normalized;
  final List<AnalysisChunk> chunks;
  final int len;
  final List<String> texts;
  final List<bool> isWordLike;
  final List<SegmentBreakKind> kinds;
  final List<int> starts;
}

/// Configuration profile passed to [analyzeText].
class AnalysisProfile {
  const AnalysisProfile({
    required this.carryCJKAfterClosingQuote,
  });

  final bool carryCJKAfterClosingQuote;
}

// ---------------------------------------------------------------------------
// Internal whitespace profile
// ---------------------------------------------------------------------------

class _WhiteSpaceProfile {
  const _WhiteSpaceProfile({
    required this.mode,
    required this.preserveOrdinarySpaces,
    required this.preserveHardBreaks,
  });

  final WhiteSpaceMode mode;
  final bool preserveOrdinarySpaces;
  final bool preserveHardBreaks;
}

_WhiteSpaceProfile _getWhiteSpaceProfile(WhiteSpaceMode mode) {
  if (mode == WhiteSpaceMode.preWrap) {
    return const _WhiteSpaceProfile(
      mode: WhiteSpaceMode.preWrap,
      preserveOrdinarySpaces: true,
      preserveHardBreaks: true,
    );
  }
  return const _WhiteSpaceProfile(
    mode: WhiteSpaceMode.normal,
    preserveOrdinarySpaces: false,
    preserveHardBreaks: false,
  );
}

// ---------------------------------------------------------------------------
// Whitespace normalisation
// ---------------------------------------------------------------------------

/// Collapses whitespace runs and trims leading/trailing spaces.
/// Matches CSS `white-space: normal` pre-processing.
String normalizeWhitespaceNormal(String text) {
  // Fast path: no normalisation needed
  if (!_needsWhitespaceNormalizationRe.hasMatch(text)) return text;

  String normalized = text.replaceAll(_collapsibleWhitespaceRunRe, ' ');
  if (normalized.isNotEmpty && normalized.codeUnitAt(0) == 0x20) {
    normalized = normalized.substring(1);
  }
  if (normalized.isNotEmpty &&
      normalized.codeUnitAt(normalized.length - 1) == 0x20) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// Normalises line endings for `white-space: pre-wrap`.
String normalizeWhitespacePreWrap(String text) {
  if (!_carriageReturnOrFormFeedRe.hasMatch(text)) {
    return text.replaceAll('\r\n', '\n');
  }
  return text
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[\r\f]'), '\n');
}

// Regex constants for whitespace normalisation
final _collapsibleWhitespaceRunRe = RegExp(r'[ \t\n\r\f]+');
final _needsWhitespaceNormalizationRe = RegExp(r'[\t\n\r\f]| {2,}|^ | $');
final _carriageReturnOrFormFeedRe = RegExp(r'[\r\f]');

// ---------------------------------------------------------------------------
// CJK detection
// ---------------------------------------------------------------------------

/// Returns true if [s] contains any CJK ideograph or adjacent script
/// character (Hiragana, Katakana, Hangul, CJK Compatibility, etc.).
bool isCJK(String s) {
  for (final rune in s.runes) {
    if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x20000 && rune <= 0x2A6DF) ||
        (rune >= 0x2A700 && rune <= 0x2B73F) ||
        (rune >= 0x2B740 && rune <= 0x2B81F) ||
        (rune >= 0x2B820 && rune <= 0x2CEAF) ||
        (rune >= 0x2CEB0 && rune <= 0x2EBEF) ||
        (rune >= 0x30000 && rune <= 0x3134F) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x2F800 && rune <= 0x2FA1F) ||
        (rune >= 0x3000 && rune <= 0x303F) ||
        (rune >= 0x3040 && rune <= 0x309F) ||
        (rune >= 0x30A0 && rune <= 0x30FF) ||
        (rune >= 0xAC00 && rune <= 0xD7AF) ||
        (rune >= 0xFF00 && rune <= 0xFFEF)) {
      return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Character sets (stored as Set<int> of Unicode code points for performance)
// ---------------------------------------------------------------------------

/// Kinsoku line-start prohibited characters (must not appear at line start).
final Set<int> kinsokuStart = {
  0xFF0C, // ，
  0xFF0E, // ．
  0xFF01, // ！
  0xFF1A, // ：
  0xFF1B, // ；
  0xFF1F, // ？
  0x3001, // 、
  0x3002, // 。
  0x30FB, // ・
  0xFF09, // ）
  0x3015, // 〕
  0x3009, // 〉
  0x300B, // 》
  0x300D, // 」
  0x300F, // 』
  0x3011, // 】
  0x3017, // 〗
  0x3019, // 〙
  0x301B, // 〛
  0x30FC, // ー
  0x3005, // 々
  0x303B, // 〻
  0x309D, // ゝ
  0x309E, // ゞ
  0x30FD, // ヽ
  0x30FE, // ヾ
};

/// Kinsoku line-end prohibited characters (must not appear at line end).
final Set<int> kinsokuEnd = {
  0x0022, // "
  0x0028, // (
  0x005B, // [
  0x007B, // {
  0x201C, // "
  0x2018, // '
  0x00AB, // «
  0x2039, // ‹
  0xFF08, // （
  0x3014, // 〔
  0x3008, // 〈
  0x300A, // 《
  0x300C, // 「
  0x300E, // 『
  0x3010, // 【
  0x3016, // 〖
  0x3018, // 〘
  0x301A, // 〚
};

/// Characters that stick forward (to the next cluster).
final Set<int> forwardStickyGlue = {
  0x0027, // '
  0x2018, // '
};

/// Punctuation that is left-sticky (attaches to the preceding word).
final Set<int> leftStickyPunctuation = {
  0x002E, // .
  0x002C, // ,
  0x0021, // !
  0x003F, // ?
  0x003A, // :
  0x003B, // ;
  0x060C, // ،
  0x061B, // ؛
  0x061F, // ؟
  0x0964, // ।
  0x0965, // ॥
  0x104A, // ၊
  0x104B, // ။
  0x104C, // ၌
  0x104D, // ၍
  0x104F, // ၏
  0x0029, // )
  0x005D, // ]
  0x007D, // }
  0x0025, // %
  0x0022, // "
  0x201D, // "
  0x2019, // '
  0x00BB, // »
  0x203A, // ›
  0x2026, // …
};

/// Arabic punctuation that does not take a space before the next word.
final Set<int> arabicNoSpaceTrailingPunctuation = {
  0x003A, // :
  0x002E, // .
  0x060C, // ،
  0x061B, // ؛
};

/// Myanmar medial glue characters.
final Set<int> myanmarMedialGlue = {
  0x104F, // ၏
};

/// Closing quote characters.
final Set<int> closingQuoteChars = {
  0x201D, // "
  0x2019, // '
  0x00BB, // »
  0x203A, // ›
  0x300D, // 」
  0x300F, // 』
  0x3011, // 】
  0x300B, // 》
  0x3009, // 〉
  0x3015, // 〕
  0xFF09, // ）
};

// ---------------------------------------------------------------------------
// Regex helpers
// ---------------------------------------------------------------------------

final _arabicScriptRe = RegExp(r'\p{Script=Arabic}', unicode: true);
final _combiningMarkRe = RegExp(r'\p{M}', unicode: true);
final _decimalDigitRe = RegExp(r'\p{Nd}', unicode: true);
final _onlyCombiningMarksRe = RegExp(r'^\p{M}+$', unicode: true);

bool _containsArabicScript(String text) => _arabicScriptRe.hasMatch(text);

// ---------------------------------------------------------------------------
// Segment classification helpers
// ---------------------------------------------------------------------------

bool _isLeftStickyPunctuationSegment(String segment) {
  if (_isEscapedQuoteClusterSegment(segment)) return true;
  bool sawPunctuation = false;
  for (final rune in segment.runes) {
    if (leftStickyPunctuation.contains(rune)) {
      sawPunctuation = true;
      continue;
    }
    if (sawPunctuation && _combiningMarkRe.hasMatch(String.fromCharCode(rune))) {
      continue;
    }
    return false;
  }
  return sawPunctuation;
}

bool _isCJKLineStartProhibitedSegment(String segment) {
  if (segment.isEmpty) return false;
  for (final rune in segment.runes) {
    if (!kinsokuStart.contains(rune) && !leftStickyPunctuation.contains(rune)) {
      return false;
    }
  }
  return true;
}

bool _isForwardStickyClusterSegment(String segment) {
  if (_isEscapedQuoteClusterSegment(segment)) return true;
  if (segment.isEmpty) return false;
  for (final rune in segment.runes) {
    final ch = String.fromCharCode(rune);
    if (!kinsokuEnd.contains(rune) &&
        !forwardStickyGlue.contains(rune) &&
        !_combiningMarkRe.hasMatch(ch)) {
      return false;
    }
  }
  return true;
}

bool _isEscapedQuoteClusterSegment(String segment) {
  bool sawQuote = false;
  for (final rune in segment.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '\\' || _combiningMarkRe.hasMatch(ch)) continue;
    if (kinsokuEnd.contains(rune) ||
        leftStickyPunctuation.contains(rune) ||
        forwardStickyGlue.contains(rune)) {
      sawQuote = true;
      continue;
    }
    return false;
  }
  return sawQuote;
}

/// Splits off any trailing forward-sticky cluster (kinsokuEnd / forwardStickyGlue
/// chars, possibly followed by combining marks) from [text].
///
/// Returns null if there is nothing to split or the entire string is sticky.
({String head, String tail})? _splitTrailingForwardStickyCluster(String text) {
  final chars = text.characters.toList();
  int splitIndex = chars.length;

  while (splitIndex > 0) {
    final ch = chars[splitIndex - 1];
    if (_combiningMarkRe.hasMatch(ch)) {
      splitIndex--;
      continue;
    }
    final rune = ch.runes.first;
    if (kinsokuEnd.contains(rune) || forwardStickyGlue.contains(rune)) {
      splitIndex--;
      continue;
    }
    break;
  }

  if (splitIndex <= 0 || splitIndex == chars.length) return null;
  return (
    head: chars.sublist(0, splitIndex).join(),
    tail: chars.sublist(splitIndex).join(),
  );
}

bool _isRepeatedSingleCharRun(String segment, String ch) {
  if (segment.isEmpty) return false;
  for (final part in segment.characters) {
    if (part != ch) return false;
  }
  return true;
}

bool _endsWithArabicNoSpacePunctuation(String segment) {
  if (segment.isEmpty || !_containsArabicScript(segment)) return false;
  final lastRune = segment.runes.last;
  return arabicNoSpaceTrailingPunctuation.contains(lastRune);
}

bool _endsWithMyanmarMedialGlue(String segment) {
  if (segment.isEmpty) return false;
  final lastRune = segment.runes.last;
  return myanmarMedialGlue.contains(lastRune);
}

({String space, String marks})? _splitLeadingSpaceAndMarks(String segment) {
  if (segment.length < 2 || segment.codeUnitAt(0) != 0x20) return null;
  final marks = segment.substring(1);
  if (_onlyCombiningMarksRe.hasMatch(marks)) {
    return (space: ' ', marks: marks);
  }
  return null;
}

/// Returns true if [text] ends with a closing quote character (possibly
/// preceded by other left-sticky punctuation).
bool endsWithClosingQuote(String text) {
  final runes = text.runes.toList();
  for (int i = runes.length - 1; i >= 0; i--) {
    if (closingQuoteChars.contains(runes[i])) return true;
    if (!leftStickyPunctuation.contains(runes[i])) return false;
  }
  return false;
}

// ---------------------------------------------------------------------------
// SegmentBreakKind classification
// ---------------------------------------------------------------------------

SegmentBreakKind _classifySegmentBreakChar(
  String ch,
  _WhiteSpaceProfile profile,
) {
  final cp = ch.runes.first;
  if (profile.preserveOrdinarySpaces || profile.preserveHardBreaks) {
    if (cp == 0x20) return SegmentBreakKind.preservedSpace;
    if (cp == 0x09) return SegmentBreakKind.tab; // \t
    if (profile.preserveHardBreaks && cp == 0x0A) {
      return SegmentBreakKind.hardBreak; // \n
    }
  }
  if (cp == 0x20) return SegmentBreakKind.space;
  // NBSP, NNBSP, WJ, BOM/ZWNBSP → glue
  if (cp == 0x00A0 || cp == 0x202F || cp == 0x2060 || cp == 0xFEFF) {
    return SegmentBreakKind.glue;
  }
  if (cp == 0x200B) return SegmentBreakKind.zeroWidthBreak; // ZWSP
  if (cp == 0x00AD) return SegmentBreakKind.softHyphen; // SHY
  return SegmentBreakKind.text;
}

// ---------------------------------------------------------------------------
// Split a word-segmenter segment by break kind
// ---------------------------------------------------------------------------

List<_SegmentationPiece> _splitSegmentByBreakKind(
  String segment,
  bool isWordLike,
  int start,
  _WhiteSpaceProfile profile,
) {
  final pieces = <_SegmentationPiece>[];
  SegmentBreakKind? currentKind;
  final currentText = StringBuffer();
  int currentStart = start;
  bool currentWordLike = false;
  int offset = 0;

  for (final grapheme in segment.characters) {
    // Use the first rune of each grapheme cluster for classification
    final kind = _classifySegmentBreakChar(
      String.fromCharCode(grapheme.runes.first),
      profile,
    );
    final wordLike = kind == SegmentBreakKind.text && isWordLike;

    if (currentKind != null &&
        kind == currentKind &&
        wordLike == currentWordLike) {
      currentText.write(grapheme);
      offset += grapheme.length;
      continue;
    }

    if (currentKind != null) {
      pieces.add(_SegmentationPiece(
        text: currentText.toString(),
        isWordLike: currentWordLike,
        kind: currentKind,
        start: currentStart,
      ));
    }

    currentKind = kind;
    currentText.clear();
    currentText.write(grapheme);
    currentStart = start + offset;
    currentWordLike = wordLike;
    offset += grapheme.length;
  }

  if (currentKind != null) {
    pieces.add(_SegmentationPiece(
      text: currentText.toString(),
      isWordLike: currentWordLike,
      kind: currentKind,
      start: currentStart,
    ));
  }

  return pieces;
}

// ---------------------------------------------------------------------------
// Custom word segmenter
// ---------------------------------------------------------------------------

/// Result of a single word-segmenter segment.
class _WordSegment {
  const _WordSegment({
    required this.segment,
    required this.isWordLike,
    required this.index,
  });

  final String segment;
  final bool isWordLike;
  final int index;
}

/// Simple Unicode word-boundary splitter using the `characters` package for
/// grapheme iteration.
///
/// The strategy:
/// 1. Special characters (spaces, NBSP, ZWSP, SHY, tabs, newlines) are always
///    their own segments with isWordLike = false.
/// 2. Runs of alphanumeric/letter characters are word-like.
/// 3. Other runs (punctuation, symbols) are non-word-like.
///
/// This is intentionally simpler than ICU word-break, but sufficient for the
/// merging pipeline to work correctly.
List<_WordSegment> _segmentWords(String text) {
  if (text.isEmpty) return const [];

  final segments = <_WordSegment>[];
  int index = 0;

  final buffer = StringBuffer();
  bool? currentWordLike;
  int segmentStart = 0;

  void flush() {
    if (buffer.isNotEmpty) {
      segments.add(_WordSegment(
        segment: buffer.toString(),
        isWordLike: currentWordLike ?? false,
        index: segmentStart,
      ));
      buffer.clear();
      currentWordLike = null;
    }
  }

  for (final grapheme in text.characters) {
    final rune = grapheme.runes.first;

    // Break-character: always its own segment
    final isBreakChar = rune == 0x20 || // space
        rune == 0x09 || // tab
        rune == 0x0A || // \n
        rune == 0x0D || // \r
        rune == 0x0C || // \f
        rune == 0x00A0 || // NBSP
        rune == 0x202F || // NNBSP
        rune == 0x2060 || // WJ
        rune == 0xFEFF || // BOM/ZWNBSP
        rune == 0x200B || // ZWSP
        rune == 0x00AD; // SHY

    if (isBreakChar) {
      flush();
      segments.add(_WordSegment(
        segment: grapheme,
        isWordLike: false,
        index: index,
      ));
      index += grapheme.length;
      segmentStart = index;
      continue;
    }

    // Determine word-like: letters and decimal digits are word-like.
    final chStr = String.fromCharCode(rune);
    final isLetter = _letterOrDigitRe.hasMatch(chStr);
    final nextWordLike = isLetter;

    if (currentWordLike != null && nextWordLike != currentWordLike) {
      flush();
      segmentStart = index;
    }

    if (buffer.isEmpty) segmentStart = index;
    buffer.write(grapheme);
    currentWordLike = nextWordLike;
    index += grapheme.length;
  }

  flush();
  return segments;
}

// Letters and decimal digits are word-like
final _letterOrDigitRe = RegExp(r'[\p{L}\p{Nd}]', unicode: true);

// ---------------------------------------------------------------------------
// Post-merge passes
// ---------------------------------------------------------------------------

bool _isTextRunBoundary(SegmentBreakKind kind) =>
    kind == SegmentBreakKind.space ||
    kind == SegmentBreakKind.preservedSpace ||
    kind == SegmentBreakKind.zeroWidthBreak ||
    kind == SegmentBreakKind.hardBreak;

final _urlSchemeSegmentRe = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*:$');

bool _isUrlLikeRunStart(MergedSegmentation seg, int index) {
  final text = seg.texts[index];
  if (text.startsWith('www.')) return true;
  return _urlSchemeSegmentRe.hasMatch(text) &&
      index + 1 < seg.len &&
      seg.kinds[index + 1] == SegmentBreakKind.text &&
      seg.texts[index + 1] == '//';
}

bool _isUrlQueryBoundarySegment(String text) =>
    text.contains('?') &&
    (text.contains('://') || text.startsWith('www.'));

MergedSegmentation _mergeUrlLikeRuns(MergedSegmentation seg) {
  final texts = seg.texts.toList();
  final isWordLike = seg.isWordLike.toList();
  final kinds = seg.kinds.toList();
  final starts = seg.starts.toList();

  for (int i = 0; i < seg.len; i++) {
    if (kinds[i] != SegmentBreakKind.text || !_isUrlLikeRunStart(seg, i)) {
      continue;
    }

    int j = i + 1;
    while (j < seg.len && !_isTextRunBoundary(kinds[j])) {
      texts[i] = texts[i] + texts[j];
      isWordLike[i] = true;
      final endsQueryPrefix = texts[j].contains('?');
      kinds[j] = SegmentBreakKind.text;
      texts[j] = '';
      j++;
      if (endsQueryPrefix) break;
    }
  }

  int compactLen = 0;
  for (int read = 0; read < texts.length; read++) {
    if (texts[read].isEmpty) continue;
    if (compactLen != read) {
      texts[compactLen] = texts[read];
      isWordLike[compactLen] = isWordLike[read];
      kinds[compactLen] = kinds[read];
      starts[compactLen] = starts[read];
    }
    compactLen++;
  }

  return MergedSegmentation(
    len: compactLen,
    texts: texts.sublist(0, compactLen),
    isWordLike: isWordLike.sublist(0, compactLen),
    kinds: kinds.sublist(0, compactLen),
    starts: starts.sublist(0, compactLen),
  );
}

MergedSegmentation _mergeUrlQueryRuns(MergedSegmentation seg) {
  final texts = <String>[];
  final isWordLike = <bool>[];
  final kinds = <SegmentBreakKind>[];
  final starts = <int>[];

  for (int i = 0; i < seg.len; i++) {
    final text = seg.texts[i];
    texts.add(text);
    isWordLike.add(seg.isWordLike[i]);
    kinds.add(seg.kinds[i]);
    starts.add(seg.starts[i]);

    if (!_isUrlQueryBoundarySegment(text)) continue;

    final nextIndex = i + 1;
    if (nextIndex >= seg.len || _isTextRunBoundary(seg.kinds[nextIndex])) {
      continue;
    }

    final queryStart = seg.starts[nextIndex];
    final queryBuffer = StringBuffer();
    int j = nextIndex;
    while (j < seg.len && !_isTextRunBoundary(seg.kinds[j])) {
      queryBuffer.write(seg.texts[j]);
      j++;
    }

    final queryText = queryBuffer.toString();
    if (queryText.isNotEmpty) {
      texts.add(queryText);
      isWordLike.add(true);
      kinds.add(SegmentBreakKind.text);
      starts.add(queryStart);
      i = j - 1;
    }
  }

  return MergedSegmentation(
    len: texts.length,
    texts: texts,
    isWordLike: isWordLike,
    kinds: kinds,
    starts: starts,
  );
}

final _numericJoinerChars = <int>{
  0x003A, // :
  0x002D, // -
  0x002F, // /
  0x00D7, // ×
  0x002C, // ,
  0x002E, // .
  0x002B, // +
  0x2013, // –
  0x2014, // —
};

final _asciiPunctuationChainSegmentRe = RegExp(r'^[A-Za-z0-9_]+[,:;]*$');
final _asciiPunctuationChainTrailingJoinersRe = RegExp(r'[,:;]+$');

bool _segmentContainsDecimalDigit(String text) {
  for (final grapheme in text.characters) {
    if (_decimalDigitRe.hasMatch(grapheme)) return true;
  }
  return false;
}

bool _isNumericRunSegment(String text) {
  if (text.isEmpty) return false;
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (_decimalDigitRe.hasMatch(ch) || _numericJoinerChars.contains(rune)) {
      continue;
    }
    return false;
  }
  return true;
}

MergedSegmentation _mergeNumericRuns(MergedSegmentation seg) {
  final texts = <String>[];
  final isWordLike = <bool>[];
  final kinds = <SegmentBreakKind>[];
  final starts = <int>[];

  for (int i = 0; i < seg.len; i++) {
    final text = seg.texts[i];
    final kind = seg.kinds[i];

    if (kind == SegmentBreakKind.text &&
        _isNumericRunSegment(text) &&
        _segmentContainsDecimalDigit(text)) {
      final mergedBuffer = StringBuffer(text);
      int j = i + 1;
      while (j < seg.len &&
          seg.kinds[j] == SegmentBreakKind.text &&
          _isNumericRunSegment(seg.texts[j])) {
        mergedBuffer.write(seg.texts[j]);
        j++;
      }

      texts.add(mergedBuffer.toString());
      isWordLike.add(true);
      kinds.add(SegmentBreakKind.text);
      starts.add(seg.starts[i]);
      i = j - 1;
      continue;
    }

    texts.add(text);
    isWordLike.add(seg.isWordLike[i]);
    kinds.add(kind);
    starts.add(seg.starts[i]);
  }

  return MergedSegmentation(
    len: texts.length,
    texts: texts,
    isWordLike: isWordLike,
    kinds: kinds,
    starts: starts,
  );
}

MergedSegmentation _mergeAsciiPunctuationChains(MergedSegmentation seg) {
  final texts = <String>[];
  final isWordLike = <bool>[];
  final kinds = <SegmentBreakKind>[];
  final starts = <int>[];

  for (int i = 0; i < seg.len; i++) {
    final text = seg.texts[i];
    final kind = seg.kinds[i];
    final wordLike = seg.isWordLike[i];

    if (kind == SegmentBreakKind.text &&
        wordLike &&
        _asciiPunctuationChainSegmentRe.hasMatch(text)) {
      final mergedBuffer = StringBuffer(text);
      int j = i + 1;

      while (_asciiPunctuationChainTrailingJoinersRe
              .hasMatch(mergedBuffer.toString()) &&
          j < seg.len &&
          seg.kinds[j] == SegmentBreakKind.text &&
          seg.isWordLike[j] &&
          _asciiPunctuationChainSegmentRe.hasMatch(seg.texts[j])) {
        mergedBuffer.write(seg.texts[j]);
        j++;
      }

      texts.add(mergedBuffer.toString());
      isWordLike.add(true);
      kinds.add(SegmentBreakKind.text);
      starts.add(seg.starts[i]);
      i = j - 1;
      continue;
    }

    texts.add(text);
    isWordLike.add(wordLike);
    kinds.add(kind);
    starts.add(seg.starts[i]);
  }

  return MergedSegmentation(
    len: texts.length,
    texts: texts,
    isWordLike: isWordLike,
    kinds: kinds,
    starts: starts,
  );
}

MergedSegmentation _splitHyphenatedNumericRuns(MergedSegmentation seg) {
  final texts = <String>[];
  final isWordLike = <bool>[];
  final kinds = <SegmentBreakKind>[];
  final starts = <int>[];

  for (int i = 0; i < seg.len; i++) {
    final text = seg.texts[i];
    if (seg.kinds[i] == SegmentBreakKind.text && text.contains('-')) {
      final parts = text.split('-');
      bool shouldSplit = parts.length > 1;
      for (final part in parts) {
        if (!shouldSplit) break;
        if (part.isEmpty ||
            !_segmentContainsDecimalDigit(part) ||
            !_isNumericRunSegment(part)) {
          shouldSplit = false;
        }
      }

      if (shouldSplit) {
        int offset = 0;
        for (int j = 0; j < parts.length; j++) {
          final part = parts[j];
          final splitText = j < parts.length - 1 ? '$part-' : part;
          texts.add(splitText);
          isWordLike.add(true);
          kinds.add(SegmentBreakKind.text);
          starts.add(seg.starts[i] + offset);
          offset += splitText.length;
        }
        continue;
      }
    }

    texts.add(text);
    isWordLike.add(seg.isWordLike[i]);
    kinds.add(seg.kinds[i]);
    starts.add(seg.starts[i]);
  }

  return MergedSegmentation(
    len: texts.length,
    texts: texts,
    isWordLike: isWordLike,
    kinds: kinds,
    starts: starts,
  );
}

MergedSegmentation _mergeGlueConnectedTextRuns(MergedSegmentation seg) {
  final texts = <String>[];
  final isWordLike = <bool>[];
  final kinds = <SegmentBreakKind>[];
  final starts = <int>[];

  int read = 0;
  while (read < seg.len) {
    String text = seg.texts[read];
    bool wordLike = seg.isWordLike[read];
    SegmentBreakKind kind = seg.kinds[read];
    int start = seg.starts[read];

    if (kind == SegmentBreakKind.glue) {
      final glueBuffer = StringBuffer(text);
      final glueStart = start;
      read++;
      while (read < seg.len && seg.kinds[read] == SegmentBreakKind.glue) {
        glueBuffer.write(seg.texts[read]);
        read++;
      }

      if (read < seg.len && seg.kinds[read] == SegmentBreakKind.text) {
        text = glueBuffer.toString() + seg.texts[read];
        wordLike = seg.isWordLike[read];
        kind = SegmentBreakKind.text;
        start = glueStart;
        read++;
      } else {
        texts.add(glueBuffer.toString());
        isWordLike.add(false);
        kinds.add(SegmentBreakKind.glue);
        starts.add(glueStart);
        continue;
      }
    } else {
      read++;
    }

    if (kind == SegmentBreakKind.text) {
      while (read < seg.len && seg.kinds[read] == SegmentBreakKind.glue) {
        final glueBuffer = StringBuffer();
        while (read < seg.len && seg.kinds[read] == SegmentBreakKind.glue) {
          glueBuffer.write(seg.texts[read]);
          read++;
        }

        if (read < seg.len && seg.kinds[read] == SegmentBreakKind.text) {
          text += glueBuffer.toString() + seg.texts[read];
          wordLike = wordLike || seg.isWordLike[read];
          read++;
          continue;
        }

        text += glueBuffer.toString();
      }
    }

    texts.add(text);
    isWordLike.add(wordLike);
    kinds.add(kind);
    starts.add(start);
  }

  return MergedSegmentation(
    len: texts.length,
    texts: texts,
    isWordLike: isWordLike,
    kinds: kinds,
    starts: starts,
  );
}

MergedSegmentation _carryTrailingForwardStickyAcrossCJKBoundary(
  MergedSegmentation seg,
) {
  final texts = seg.texts.toList();
  final isWordLike = seg.isWordLike.toList();
  final kinds = seg.kinds.toList();
  final starts = seg.starts.toList();

  for (int i = 0; i < texts.length - 1; i++) {
    if (kinds[i] != SegmentBreakKind.text ||
        kinds[i + 1] != SegmentBreakKind.text) {
      continue;
    }
    if (!isCJK(texts[i]) || !isCJK(texts[i + 1])) continue;

    final split = _splitTrailingForwardStickyCluster(texts[i]);
    if (split == null) continue;

    texts[i] = split.head;
    texts[i + 1] = split.tail + texts[i + 1];
    starts[i + 1] = starts[i] + split.head.length;
  }

  return MergedSegmentation(
    len: texts.length,
    texts: texts,
    isWordLike: isWordLike,
    kinds: kinds,
    starts: starts,
  );
}

// ---------------------------------------------------------------------------
// Main merging pipeline
// ---------------------------------------------------------------------------

MergedSegmentation _buildMergedSegmentation(
  String normalized,
  AnalysisProfile profile,
  _WhiteSpaceProfile whiteSpaceProfile,
) {
  int mergedLen = 0;
  final mergedTexts = <String>[];
  final mergedWordLike = <bool>[];
  final mergedKinds = <SegmentBreakKind>[];
  final mergedStarts = <int>[];

  for (final wordSeg in _segmentWords(normalized)) {
    for (final piece in _splitSegmentByBreakKind(
      wordSeg.segment,
      wordSeg.isWordLike,
      wordSeg.index,
      whiteSpaceProfile,
    )) {
      final isText = piece.kind == SegmentBreakKind.text;

      if (profile.carryCJKAfterClosingQuote &&
          isText &&
          mergedLen > 0 &&
          mergedKinds[mergedLen - 1] == SegmentBreakKind.text &&
          isCJK(piece.text) &&
          isCJK(mergedTexts[mergedLen - 1]) &&
          endsWithClosingQuote(mergedTexts[mergedLen - 1])) {
        mergedTexts[mergedLen - 1] =
            mergedTexts[mergedLen - 1] + piece.text;
        mergedWordLike[mergedLen - 1] =
            mergedWordLike[mergedLen - 1] || piece.isWordLike;
      } else if (isText &&
          mergedLen > 0 &&
          mergedKinds[mergedLen - 1] == SegmentBreakKind.text &&
          _isCJKLineStartProhibitedSegment(piece.text) &&
          isCJK(mergedTexts[mergedLen - 1])) {
        mergedTexts[mergedLen - 1] =
            mergedTexts[mergedLen - 1] + piece.text;
        mergedWordLike[mergedLen - 1] =
            mergedWordLike[mergedLen - 1] || piece.isWordLike;
      } else if (isText &&
          mergedLen > 0 &&
          mergedKinds[mergedLen - 1] == SegmentBreakKind.text &&
          _endsWithMyanmarMedialGlue(mergedTexts[mergedLen - 1])) {
        mergedTexts[mergedLen - 1] =
            mergedTexts[mergedLen - 1] + piece.text;
        mergedWordLike[mergedLen - 1] =
            mergedWordLike[mergedLen - 1] || piece.isWordLike;
      } else if (isText &&
          mergedLen > 0 &&
          mergedKinds[mergedLen - 1] == SegmentBreakKind.text &&
          piece.isWordLike &&
          _containsArabicScript(piece.text) &&
          _endsWithArabicNoSpacePunctuation(mergedTexts[mergedLen - 1])) {
        mergedTexts[mergedLen - 1] =
            mergedTexts[mergedLen - 1] + piece.text;
        mergedWordLike[mergedLen - 1] = true;
      } else if (isText &&
          !piece.isWordLike &&
          mergedLen > 0 &&
          mergedKinds[mergedLen - 1] == SegmentBreakKind.text &&
          piece.text.length == 1 &&
          piece.text != '-' &&
          piece.text != '\u2014' &&
          _isRepeatedSingleCharRun(mergedTexts[mergedLen - 1], piece.text)) {
        mergedTexts[mergedLen - 1] =
            mergedTexts[mergedLen - 1] + piece.text;
      } else if (isText &&
          !piece.isWordLike &&
          mergedLen > 0 &&
          mergedKinds[mergedLen - 1] == SegmentBreakKind.text &&
          (_isLeftStickyPunctuationSegment(piece.text) ||
              (piece.text == '-' && mergedWordLike[mergedLen - 1]))) {
        mergedTexts[mergedLen - 1] =
            mergedTexts[mergedLen - 1] + piece.text;
      } else {
        if (mergedLen < mergedTexts.length) {
          mergedTexts[mergedLen] = piece.text;
          mergedWordLike[mergedLen] = piece.isWordLike;
          mergedKinds[mergedLen] = piece.kind;
          mergedStarts[mergedLen] = piece.start;
        } else {
          mergedTexts.add(piece.text);
          mergedWordLike.add(piece.isWordLike);
          mergedKinds.add(piece.kind);
          mergedStarts.add(piece.start);
        }
        mergedLen++;
      }
    }
  }

  // Pass 1: forward escaped-quote cluster merging
  for (int i = 1; i < mergedLen; i++) {
    if (mergedKinds[i] == SegmentBreakKind.text &&
        !mergedWordLike[i] &&
        _isEscapedQuoteClusterSegment(mergedTexts[i]) &&
        mergedKinds[i - 1] == SegmentBreakKind.text) {
      mergedTexts[i - 1] = mergedTexts[i - 1] + mergedTexts[i];
      mergedWordLike[i - 1] = mergedWordLike[i - 1] || mergedWordLike[i];
      mergedTexts[i] = '';
    }
  }

  // Pass 2: backward forward-sticky cluster carry
  for (int i = mergedLen - 2; i >= 0; i--) {
    if (mergedKinds[i] == SegmentBreakKind.text &&
        !mergedWordLike[i] &&
        _isForwardStickyClusterSegment(mergedTexts[i])) {
      int j = i + 1;
      while (j < mergedLen && mergedTexts[j].isEmpty) {
        j++;
      }
      if (j < mergedLen && mergedKinds[j] == SegmentBreakKind.text) {
        mergedTexts[j] = mergedTexts[i] + mergedTexts[j];
        mergedStarts[j] = mergedStarts[i];
        mergedTexts[i] = '';
      }
    }
  }

  // Compact out empty entries
  int compactLen = 0;
  for (int read = 0; read < mergedLen; read++) {
    if (mergedTexts[read].isEmpty) continue;
    if (compactLen != read) {
      mergedTexts[compactLen] = mergedTexts[read];
      mergedWordLike[compactLen] = mergedWordLike[read];
      mergedKinds[compactLen] = mergedKinds[read];
      mergedStarts[compactLen] = mergedStarts[read];
    }
    compactLen++;
  }

  final compacted = _mergeGlueConnectedTextRuns(MergedSegmentation(
    len: compactLen,
    texts: mergedTexts.sublist(0, compactLen),
    isWordLike: mergedWordLike.sublist(0, compactLen),
    kinds: mergedKinds.sublist(0, compactLen),
    starts: mergedStarts.sublist(0, compactLen),
  ));

  final withMergedUrls = _carryTrailingForwardStickyAcrossCJKBoundary(
    _mergeAsciiPunctuationChains(
      _splitHyphenatedNumericRuns(
        _mergeNumericRuns(
          _mergeUrlQueryRuns(
            _mergeUrlLikeRuns(compacted),
          ),
        ),
      ),
    ),
  );

  // Arabic combining-mark fixup: split " " + marks from a space segment when
  // the next text segment contains Arabic script.
  for (int i = 0; i < withMergedUrls.len - 1; i++) {
    final split = _splitLeadingSpaceAndMarks(withMergedUrls.texts[i]);
    if (split == null) continue;
    if ((withMergedUrls.kinds[i] != SegmentBreakKind.space &&
            withMergedUrls.kinds[i] != SegmentBreakKind.preservedSpace) ||
        withMergedUrls.kinds[i + 1] != SegmentBreakKind.text ||
        !_containsArabicScript(withMergedUrls.texts[i + 1])) {
      continue;
    }

    withMergedUrls.texts[i] = split.space;
    withMergedUrls.isWordLike[i] = false;
    // kind stays the same (space or preserved-space)
    withMergedUrls.texts[i + 1] =
        split.marks + withMergedUrls.texts[i + 1];
    withMergedUrls.starts[i + 1] =
        withMergedUrls.starts[i] + split.space.length;
  }

  return withMergedUrls;
}

// ---------------------------------------------------------------------------
// Hard-break chunk compilation
// ---------------------------------------------------------------------------

List<AnalysisChunk> _compileAnalysisChunks(
  MergedSegmentation seg,
  _WhiteSpaceProfile profile,
) {
  if (seg.len == 0) return const [];

  if (!profile.preserveHardBreaks) {
    return [
      AnalysisChunk(
        startSegmentIndex: 0,
        endSegmentIndex: seg.len,
        consumedEndSegmentIndex: seg.len,
      )
    ];
  }

  final chunks = <AnalysisChunk>[];
  int startSegmentIndex = 0;

  for (int i = 0; i < seg.len; i++) {
    if (seg.kinds[i] != SegmentBreakKind.hardBreak) continue;

    chunks.add(AnalysisChunk(
      startSegmentIndex: startSegmentIndex,
      endSegmentIndex: i,
      consumedEndSegmentIndex: i + 1,
    ));
    startSegmentIndex = i + 1;
  }

  if (startSegmentIndex < seg.len) {
    chunks.add(AnalysisChunk(
      startSegmentIndex: startSegmentIndex,
      endSegmentIndex: seg.len,
      consumedEndSegmentIndex: seg.len,
    ));
  }

  return chunks;
}

// ---------------------------------------------------------------------------
// Top-level entry point
// ---------------------------------------------------------------------------

/// Analyses [text] with the given [profile] and [whiteSpace] mode, returning
/// a [TextAnalysis] with the normalised string, merged segments, and
/// hard-break chunks.
TextAnalysis analyzeText(
  String text,
  AnalysisProfile profile, [
  WhiteSpaceMode whiteSpace = WhiteSpaceMode.normal,
]) {
  final whiteSpaceProfile = _getWhiteSpaceProfile(whiteSpace);
  final normalized = whiteSpaceProfile.mode == WhiteSpaceMode.preWrap
      ? normalizeWhitespacePreWrap(text)
      : normalizeWhitespaceNormal(text);

  if (normalized.isEmpty) {
    return const TextAnalysis(
      normalized: '',
      chunks: [],
      len: 0,
      texts: [],
      isWordLike: [],
      kinds: [],
      starts: [],
    );
  }

  final seg = _buildMergedSegmentation(normalized, profile, whiteSpaceProfile);
  return TextAnalysis(
    normalized: normalized,
    chunks: _compileAnalysisChunks(seg, whiteSpaceProfile),
    len: seg.len,
    texts: seg.texts,
    isWordLike: seg.isWordLike,
    kinds: seg.kinds,
    starts: seg.starts,
  );
}
