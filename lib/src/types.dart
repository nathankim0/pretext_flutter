/// White space handling mode for text preparation.
enum WhiteSpaceMode {
  /// Collapse whitespace runs into single spaces, trim leading/trailing.
  /// Matches CSS `white-space: normal`.
  normal,

  /// Preserve ordinary spaces, tabs, and hard breaks.
  /// Matches CSS `white-space: pre-wrap`.
  preWrap,
}

/// Classification of a segment's break behavior.
enum SegmentBreakKind {
  text,
  space,
  preservedSpace,
  tab,
  glue,
  zeroWidthBreak,
  softHyphen,
  hardBreak,
}

/// Cursor position within prepared segments.
class LayoutCursor {
  const LayoutCursor({
    required this.segmentIndex,
    required this.graphemeIndex,
  });

  /// Segment index in prepared segments array.
  final int segmentIndex;

  /// Grapheme index within that segment; `0` at segment boundaries.
  final int graphemeIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutCursor &&
          segmentIndex == other.segmentIndex &&
          graphemeIndex == other.graphemeIndex;

  @override
  int get hashCode => Object.hash(segmentIndex, graphemeIndex);

  @override
  String toString() =>
      'LayoutCursor(segment: $segmentIndex, grapheme: $graphemeIndex)';
}

/// Result of a layout pass: line count and total height.
class LayoutResult {
  const LayoutResult({
    required this.lineCount,
    required this.height,
  });

  /// Number of wrapped lines.
  final int lineCount;

  /// Total block height = lineCount * lineHeight.
  final double height;

  @override
  String toString() => 'LayoutResult(lines: $lineCount, height: $height)';
}

/// A single laid-out line with text content, width, and cursor boundaries.
class LayoutLine {
  const LayoutLine({
    required this.text,
    required this.width,
    required this.start,
    required this.end,
  });

  /// Full text content of this line.
  final String text;

  /// Measured width of this line.
  final double width;

  /// Inclusive start cursor in prepared segments/graphemes.
  final LayoutCursor start;

  /// Exclusive end cursor in prepared segments/graphemes.
  final LayoutCursor end;

  @override
  String toString() => 'LayoutLine("$text", width: $width)';
}

/// Line geometry without materialized text (for shrinkwrap / aggregate work).
class LayoutLineRange {
  const LayoutLineRange({
    required this.width,
    required this.start,
    required this.end,
  });

  /// Measured width of this line.
  final double width;

  /// Inclusive start cursor.
  final LayoutCursor start;

  /// Exclusive end cursor.
  final LayoutCursor end;
}

/// Result of [layoutWithLines]: layout result plus per-line details.
class LayoutLinesResult {
  const LayoutLinesResult({
    required this.lineCount,
    required this.height,
    required this.lines,
  });

  /// Number of wrapped lines.
  final int lineCount;

  /// Total block height = lineCount * lineHeight.
  final double height;

  /// Per-line text, width, and cursor pairs for custom rendering.
  final List<LayoutLine> lines;
}

/// Pre-compiled hard-break chunk for line walking.
class PreparedLineChunk {
  const PreparedLineChunk({
    required this.startSegmentIndex,
    required this.endSegmentIndex,
    required this.consumedEndSegmentIndex,
  });

  final int startSegmentIndex;
  final int endSegmentIndex;
  final int consumedEndSegmentIndex;
}

/// Internal core data backing a prepared text handle.
class PreparedCore {
  PreparedCore({
    required this.widths,
    required this.lineEndFitAdvances,
    required this.lineEndPaintAdvances,
    required this.kinds,
    required this.simpleLineWalkFastPath,
    required this.breakableWidths,
    required this.breakablePrefixWidths,
    required this.discretionaryHyphenWidth,
    required this.tabStopAdvance,
    required this.chunks,
  });

  /// Segment widths.
  final List<double> widths;

  /// Width contribution when a line ends after this segment (fit).
  final List<double> lineEndFitAdvances;

  /// Painted width contribution when a line ends after this segment.
  final List<double> lineEndPaintAdvances;

  /// Break behavior per segment.
  final List<SegmentBreakKind> kinds;

  /// Normal text can use the simpler old line walker.
  final bool simpleLineWalkFastPath;

  /// Grapheme widths for overflow-wrap segments, else null.
  final List<List<double>?> breakableWidths;

  /// Cumulative grapheme prefix widths.
  final List<List<double>?> breakablePrefixWidths;

  /// Visible width added when a soft hyphen break is chosen.
  final double discretionaryHyphenWidth;

  /// Absolute advance between tab stops for pre-wrap tab segments.
  final double tabStopAdvance;

  /// Pre-compiled hard-break chunks.
  final List<PreparedLineChunk> chunks;
}

/// Opaque handle returned by [prepare]. Pass to [layout] for arithmetic-only
/// relayout at any width.
class PreparedText {
  PreparedText(this._core);

  final PreparedCore _core;

  /// Access the internal core data.
  PreparedCore get core => _core;
}

/// Rich variant of [PreparedText] that exposes structural segment data
/// for custom rendering.
class PreparedTextWithSegments extends PreparedText {
  PreparedTextWithSegments(
    super.core, {
    required this.segments,
  });

  /// Segment text aligned with the parallel arrays.
  final List<String> segments;
}
