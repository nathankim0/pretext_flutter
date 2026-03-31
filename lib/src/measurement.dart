import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'analysis.dart';

/// Fixed line-fit tolerance (replaces browser-specific epsilon).
const double lineFitEpsilon = 0.005;

/// Global shared measurer instance.
SegmentMeasurer segmentMeasurer = SegmentMeasurer();

/// Replace the global measurer for testing. Resets to default when set to null.
@visibleForTesting
set testMeasurer(SegmentMeasurer? measurer) {
  segmentMeasurer = measurer ?? SegmentMeasurer();
}

/// Measures text segment widths via TextPainter with caching.
///
/// Cache structure: TextStyle → segment string → width
/// Shared across all prepare() calls for the same font.
class SegmentMeasurer {
  /// Cache keyed by TextStyle (uses TextStyle equality/hashCode).
  final Map<TextStyle, Map<String, double>> _widthCache = {};

  /// Measure a text segment's width, returning cached value if available.
  double measureSegment(String segment, TextStyle style) {
    final styleCache = _widthCache.putIfAbsent(style, () => {});
    final cached = styleCache[segment];
    if (cached != null) return cached;

    final painter = TextPainter(
      text: TextSpan(text: segment, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final width = painter.width;
    painter.dispose();
    styleCache[segment] = width;
    return width;
  }

  /// Measure individual grapheme widths within a segment.
  ///
  /// Returns null if segment has only 1 grapheme (no point in breaking).
  List<double>? measureGraphemeWidths(String segment, TextStyle style) {
    final graphemes = segment.characters;
    if (graphemes.length <= 1) return null;

    final widths = <double>[];
    for (final grapheme in graphemes) {
      widths.add(measureSegment(grapheme, style));
    }
    return widths;
  }

  /// Measure cumulative prefix widths (captures kerning/ligature effects).
  ///
  /// Measures prefixes: "h", "he", "hel", "hell", "hello"
  /// Returns null if segment has only 1 grapheme.
  List<double>? measureGraphemePrefixWidths(String segment, TextStyle style) {
    final graphemes = segment.characters;
    if (graphemes.length <= 1) return null;

    final prefixWidths = <double>[];
    var prefix = '';
    for (final grapheme in graphemes) {
      prefix += grapheme;
      prefixWidths.add(measureSegment(prefix, style));
    }
    return prefixWidths;
  }

  /// Whether a segment contains CJK characters.
  bool containsCJK(String segment) => isCJK(segment);

  /// Clear all cached measurements.
  void clearCache() {
    _widthCache.clear();
  }
}
