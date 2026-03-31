/// Pure Dart text measurement & layout library.
///
/// Port of [chenglou/pretext](https://github.com/chenglou/pretext).
/// Segments text once, caches widths, then performs pure arithmetic
/// for layout at any width.
library;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

import 'src/analysis.dart';
import 'src/line_break.dart';
import 'src/measurement.dart';
import 'src/types.dart';

export 'src/types.dart'
    show
        WhiteSpaceMode,
        LayoutCursor,
        LayoutResult,
        LayoutLine,
        LayoutLineRange,
        LayoutLinesResult,
        PreparedText,
        PreparedTextWithSegments;

// ---------------------------------------------------------------------------
// Shared state
// ---------------------------------------------------------------------------

final _graphemeCache =
    Expando<Map<int, List<String>>>('pretextGraphemeCache');

Map<int, List<String>> _getLineTextCache(PreparedTextWithSegments prepared) {
  var cache = _graphemeCache[prepared];
  if (cache != null) return cache;
  cache = <int, List<String>>{};
  _graphemeCache[prepared] = cache;
  return cache;
}

List<String> _getSegmentGraphemes(
  int segmentIndex,
  List<String> segments,
  Map<int, List<String>> cache,
) {
  var graphemes = cache[segmentIndex];
  if (graphemes != null) return graphemes;

  graphemes = segments[segmentIndex].characters.toList();
  cache[segmentIndex] = graphemes;
  return graphemes;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Prepare text for layout. Segments the text, measures each segment via
/// [TextPainter], and stores the widths for fast relayout at any width.
///
/// Call once per text block (e.g. when a comment first appears). The result
/// is width-independent — the same [PreparedText] can be laid out at any
/// [maxWidth] and [lineHeight] via [layout].
///
/// The [style] parameter must match the [TextStyle] used to render the text.
PreparedText prepare(
  String text,
  TextStyle style, {
  WhiteSpaceMode whiteSpace = WhiteSpaceMode.normal,
}) {
  return _prepareInternal(text, style, false, whiteSpace);
}

/// Rich variant of [prepare] that also exposes the structural segment data
/// for manual line layout and custom rendering.
PreparedTextWithSegments prepareWithSegments(
  String text,
  TextStyle style, {
  WhiteSpaceMode whiteSpace = WhiteSpaceMode.normal,
}) {
  return _prepareInternal(text, style, true, whiteSpace)
      as PreparedTextWithSegments;
}

/// Layout prepared text at a given max width and caller-provided [lineHeight].
///
/// Pure arithmetic on cached widths — no [TextPainter] calls, no allocations.
/// Call on every resize.
LayoutResult layout(
  PreparedText prepared,
  double maxWidth,
  double lineHeight,
) {
  final lineCount = countPreparedLines(prepared.core, maxWidth);
  return LayoutResult(lineCount: lineCount, height: lineCount * lineHeight);
}

/// Rich layout API returning actual line contents and widths.
///
/// Mirrors [layout]'s break decisions but keeps extra per-line bookkeeping.
/// Should stay off the resize hot path.
LayoutLinesResult layoutWithLines(
  PreparedTextWithSegments prepared,
  double maxWidth,
  double lineHeight,
) {
  final lines = <LayoutLine>[];
  if (prepared.core.widths.isEmpty) {
    return LayoutLinesResult(lineCount: 0, height: 0, lines: lines);
  }

  final graphemeCache = _getLineTextCache(prepared);
  final lineCount = walkPreparedLines(prepared.core, maxWidth, (line) {
    lines.add(_materializeLayoutLine(prepared, graphemeCache, line));
  });

  return LayoutLinesResult(
    lineCount: lineCount,
    height: lineCount * lineHeight,
    lines: lines,
  );
}

/// Batch low-level line geometry pass without materializing text strings.
///
/// Useful for shrinkwrap and aggregate layout work.
/// Returns the total line count.
int walkLineRanges(
  PreparedTextWithSegments prepared,
  double maxWidth,
  void Function(LayoutLineRange line) onLine,
) {
  if (prepared.core.widths.isEmpty) return 0;

  return walkPreparedLines(prepared.core, maxWidth, (line) {
    onLine(_toLayoutLineRange(line));
  });
}

/// Iterator-like API for laying out each line with a different width.
///
/// Returns the [LayoutLine] starting from [start], or `null` when the
/// paragraph is exhausted. Pass the previous line's `end` cursor as the
/// next [start].
LayoutLine? layoutNextLine(
  PreparedTextWithSegments prepared,
  LayoutCursor start,
  double maxWidth,
) {
  final line = _stepLineRange(prepared, start, maxWidth);
  if (line == null) return null;
  return _materializeLine(prepared, line);
}

/// Clear all internal caches used by [prepare] and [prepareWithSegments].
void clearCache() {
  segmentMeasurer.clearCache();
}

// ---------------------------------------------------------------------------
// Internal: measure analysis into prepared data
// ---------------------------------------------------------------------------

PreparedText _prepareInternal(
  String text,
  TextStyle style,
  bool includeSegments,
  WhiteSpaceMode whiteSpace,
) {
  // The analysis profile controls CJK closing-quote carry behavior.
  // We default to false (non-Chromium behavior) since Flutter is not a browser.
  const profile = AnalysisProfile(carryCJKAfterClosingQuote: false);
  final analysis = analyzeText(text, profile, whiteSpace);
  return _measureAnalysis(analysis, style, includeSegments);
}

PreparedText _measureAnalysis(
  TextAnalysis analysis,
  TextStyle style,
  bool includeSegments,
) {
  final measurer = segmentMeasurer;
  final discretionaryHyphenWidth = measurer.measureSegment('-', style);
  final spaceWidth = measurer.measureSegment(' ', style);
  final tabStopAdvance = spaceWidth * 8;

  if (analysis.len == 0) {
    return _createEmptyPrepared(includeSegments);
  }

  final widths = <double>[];
  final lineEndFitAdvances = <double>[];
  final lineEndPaintAdvances = <double>[];
  final kinds = <SegmentBreakKind>[];
  var simpleLineWalkFastPath = analysis.chunks.length <= 1;
  final breakableWidths = <List<double>?>[];
  final breakablePrefixWidths = <List<double>?>[];
  final segments = includeSegments ? <String>[] : null;
  final segStarts = includeSegments ? <int>[] : null;
  final preparedStartByAnalysisIndex = List<int>.filled(analysis.len, 0);
  final preparedEndByAnalysisIndex = List<int>.filled(analysis.len, 0);

  void pushMeasuredSegment(
    String text,
    double width,
    double lineEndFitAdvance,
    double lineEndPaintAdvance,
    SegmentBreakKind kind,
    int start,
    List<double>? breakable,
    List<double>? breakablePrefix,
  ) {
    if (kind != SegmentBreakKind.text &&
        kind != SegmentBreakKind.space &&
        kind != SegmentBreakKind.zeroWidthBreak) {
      simpleLineWalkFastPath = false;
    }
    widths.add(width);
    lineEndFitAdvances.add(lineEndFitAdvance);
    lineEndPaintAdvances.add(lineEndPaintAdvance);
    kinds.add(kind);
    segStarts?.add(start);
    breakableWidths.add(breakable);
    breakablePrefixWidths.add(breakablePrefix);
    segments?.add(text);
  }

  for (int mi = 0; mi < analysis.len; mi++) {
    preparedStartByAnalysisIndex[mi] = widths.length;
    final segText = analysis.texts[mi];
    final segWordLike = analysis.isWordLike[mi];
    final segKind = analysis.kinds[mi];
    final segStart = analysis.starts[mi];

    if (segKind == SegmentBreakKind.softHyphen) {
      pushMeasuredSegment(
        segText,
        0,
        discretionaryHyphenWidth,
        discretionaryHyphenWidth,
        segKind,
        segStart,
        null,
        null,
      );
      preparedEndByAnalysisIndex[mi] = widths.length;
      continue;
    }

    if (segKind == SegmentBreakKind.hardBreak) {
      pushMeasuredSegment(segText, 0, 0, 0, segKind, segStart, null, null);
      preparedEndByAnalysisIndex[mi] = widths.length;
      continue;
    }

    if (segKind == SegmentBreakKind.tab) {
      pushMeasuredSegment(segText, 0, 0, 0, segKind, segStart, null, null);
      preparedEndByAnalysisIndex[mi] = widths.length;
      continue;
    }

    final w = measurer.measureSegment(segText, style);
    final containsCJK = isCJK(segText);

    if (segKind == SegmentBreakKind.text && containsCJK) {
      // Split CJK segments into individual graphemes with kinsoku merging.
      var unitText = '';
      var unitStart = 0;
      var graphemeIndex = 0;

      for (final grapheme in segText.characters) {
        if (unitText.isEmpty) {
          unitText = grapheme;
          unitStart = graphemeIndex;
          graphemeIndex += grapheme.length;
          continue;
        }

        final graphemeRune = grapheme.runes.first;
        if (kinsokuEnd.contains(unitText.runes.first) ||
            kinsokuStart.contains(graphemeRune) ||
            leftStickyPunctuation.contains(graphemeRune) ||
            (isCJK(grapheme) && endsWithClosingQuote(unitText))) {
          unitText += grapheme;
          graphemeIndex += grapheme.length;
          continue;
        }

        final unitW = measurer.measureSegment(unitText, style);
        pushMeasuredSegment(
          unitText,
          unitW,
          unitW,
          unitW,
          SegmentBreakKind.text,
          segStart + unitStart,
          null,
          null,
        );

        unitText = grapheme;
        unitStart = graphemeIndex;
        graphemeIndex += grapheme.length;
      }

      if (unitText.isNotEmpty) {
        final unitW = measurer.measureSegment(unitText, style);
        pushMeasuredSegment(
          unitText,
          unitW,
          unitW,
          unitW,
          SegmentBreakKind.text,
          segStart + unitStart,
          null,
          null,
        );
      }
      preparedEndByAnalysisIndex[mi] = widths.length;
      continue;
    }

    final lineEndFitAdv =
        (segKind == SegmentBreakKind.space ||
                segKind == SegmentBreakKind.preservedSpace ||
                segKind == SegmentBreakKind.zeroWidthBreak)
            ? 0.0
            : w;
    final lineEndPaintAdv =
        (segKind == SegmentBreakKind.space ||
                segKind == SegmentBreakKind.zeroWidthBreak)
            ? 0.0
            : w;

    if (segWordLike && segText.length > 1) {
      final graphemeWidths = measurer.measureGraphemeWidths(segText, style);
      pushMeasuredSegment(
        segText,
        w,
        lineEndFitAdv,
        lineEndPaintAdv,
        segKind,
        segStart,
        graphemeWidths,
        null, // prefix widths not needed (preferPrefixWidths = false)
      );
    } else {
      pushMeasuredSegment(
        segText,
        w,
        lineEndFitAdv,
        lineEndPaintAdv,
        segKind,
        segStart,
        null,
        null,
      );
    }
    preparedEndByAnalysisIndex[mi] = widths.length;
  }

  final chunks = _mapAnalysisChunksToPreparedChunks(
    analysis.chunks,
    preparedStartByAnalysisIndex,
    preparedEndByAnalysisIndex,
  );

  final core = PreparedCore(
    widths: widths,
    lineEndFitAdvances: lineEndFitAdvances,
    lineEndPaintAdvances: lineEndPaintAdvances,
    kinds: kinds,
    simpleLineWalkFastPath: simpleLineWalkFastPath,
    breakableWidths: breakableWidths,
    breakablePrefixWidths: breakablePrefixWidths,
    discretionaryHyphenWidth: discretionaryHyphenWidth,
    tabStopAdvance: tabStopAdvance,
    chunks: chunks,
  );

  if (segments != null) {
    return PreparedTextWithSegments(core, segments: segments);
  }
  return PreparedText(core);
}

PreparedText _createEmptyPrepared(bool includeSegments) {
  final core = PreparedCore(
    widths: [],
    lineEndFitAdvances: [],
    lineEndPaintAdvances: [],
    kinds: [],
    simpleLineWalkFastPath: true,
    breakableWidths: [],
    breakablePrefixWidths: [],
    discretionaryHyphenWidth: 0,
    tabStopAdvance: 0,
    chunks: [],
  );
  if (includeSegments) {
    return PreparedTextWithSegments(core, segments: []);
  }
  return PreparedText(core);
}

List<PreparedLineChunk> _mapAnalysisChunksToPreparedChunks(
  List<AnalysisChunk> chunks,
  List<int> preparedStartByAnalysisIndex,
  List<int> preparedEndByAnalysisIndex,
) {
  final result = <PreparedLineChunk>[];
  for (final chunk in chunks) {
    final startIdx = chunk.startSegmentIndex < preparedStartByAnalysisIndex.length
        ? preparedStartByAnalysisIndex[chunk.startSegmentIndex]
        : (preparedEndByAnalysisIndex.isNotEmpty
            ? preparedEndByAnalysisIndex.last
            : 0);
    final endIdx = chunk.endSegmentIndex < preparedStartByAnalysisIndex.length
        ? preparedStartByAnalysisIndex[chunk.endSegmentIndex]
        : (preparedEndByAnalysisIndex.isNotEmpty
            ? preparedEndByAnalysisIndex.last
            : 0);
    final consumedIdx = chunk.consumedEndSegmentIndex <
            preparedStartByAnalysisIndex.length
        ? preparedStartByAnalysisIndex[chunk.consumedEndSegmentIndex]
        : (preparedEndByAnalysisIndex.isNotEmpty
            ? preparedEndByAnalysisIndex.last
            : 0);
    result.add(PreparedLineChunk(
      startSegmentIndex: startIdx,
      endSegmentIndex: endIdx,
      consumedEndSegmentIndex: consumedIdx,
    ));
  }
  return result;
}

// ---------------------------------------------------------------------------
// Internal: line text materialization
// ---------------------------------------------------------------------------

bool _lineHasDiscretionaryHyphen(
  List<SegmentBreakKind> kinds,
  int startSegmentIndex,
  int startGraphemeIndex,
  int endSegmentIndex,
) {
  return endSegmentIndex > 0 &&
      kinds[endSegmentIndex - 1] == SegmentBreakKind.softHyphen &&
      !(startSegmentIndex == endSegmentIndex && startGraphemeIndex > 0);
}

String _buildLineTextFromRange(
  List<String> segments,
  List<SegmentBreakKind> kinds,
  Map<int, List<String>> cache,
  int startSegmentIndex,
  int startGraphemeIndex,
  int endSegmentIndex,
  int endGraphemeIndex,
) {
  final buf = StringBuffer();
  final endsWithDiscretionaryHyphen = _lineHasDiscretionaryHyphen(
    kinds,
    startSegmentIndex,
    startGraphemeIndex,
    endSegmentIndex,
  );

  for (int i = startSegmentIndex; i < endSegmentIndex; i++) {
    if (kinds[i] == SegmentBreakKind.softHyphen ||
        kinds[i] == SegmentBreakKind.hardBreak) {
      continue;
    }
    if (i == startSegmentIndex && startGraphemeIndex > 0) {
      buf.write(
        _getSegmentGraphemes(i, segments, cache)
            .sublist(startGraphemeIndex)
            .join(),
      );
    } else {
      buf.write(segments[i]);
    }
  }

  if (endGraphemeIndex > 0) {
    if (endsWithDiscretionaryHyphen) buf.write('-');
    buf.write(
      _getSegmentGraphemes(endSegmentIndex, segments, cache)
          .sublist(
            startSegmentIndex == endSegmentIndex ? startGraphemeIndex : 0,
            endGraphemeIndex,
          )
          .join(),
    );
  } else if (endsWithDiscretionaryHyphen) {
    buf.write('-');
  }

  return buf.toString();
}

LayoutLine _createLayoutLine(
  PreparedTextWithSegments prepared,
  Map<int, List<String>> cache,
  double width,
  int startSegmentIndex,
  int startGraphemeIndex,
  int endSegmentIndex,
  int endGraphemeIndex,
) {
  return LayoutLine(
    text: _buildLineTextFromRange(
      prepared.segments,
      prepared.core.kinds,
      cache,
      startSegmentIndex,
      startGraphemeIndex,
      endSegmentIndex,
      endGraphemeIndex,
    ),
    width: width,
    start: LayoutCursor(
      segmentIndex: startSegmentIndex,
      graphemeIndex: startGraphemeIndex,
    ),
    end: LayoutCursor(
      segmentIndex: endSegmentIndex,
      graphemeIndex: endGraphemeIndex,
    ),
  );
}

LayoutLine _materializeLayoutLine(
  PreparedTextWithSegments prepared,
  Map<int, List<String>> cache,
  InternalLayoutLine line,
) {
  return _createLayoutLine(
    prepared,
    cache,
    line.width,
    line.startSegmentIndex,
    line.startGraphemeIndex,
    line.endSegmentIndex,
    line.endGraphemeIndex,
  );
}

LayoutLineRange _toLayoutLineRange(InternalLayoutLine line) {
  return LayoutLineRange(
    width: line.width,
    start: LayoutCursor(
      segmentIndex: line.startSegmentIndex,
      graphemeIndex: line.startGraphemeIndex,
    ),
    end: LayoutCursor(
      segmentIndex: line.endSegmentIndex,
      graphemeIndex: line.endGraphemeIndex,
    ),
  );
}

LayoutLineRange? _stepLineRange(
  PreparedTextWithSegments prepared,
  LayoutCursor start,
  double maxWidth,
) {
  final line = layoutNextLineRange(prepared.core, start, maxWidth);
  if (line == null) return null;
  return _toLayoutLineRange(line);
}

LayoutLine _materializeLine(
  PreparedTextWithSegments prepared,
  LayoutLineRange line,
) {
  return _createLayoutLine(
    prepared,
    _getLineTextCache(prepared),
    line.width,
    line.start.segmentIndex,
    line.start.graphemeIndex,
    line.end.segmentIndex,
    line.end.graphemeIndex,
  );
}
