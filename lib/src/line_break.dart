import 'types.dart';

// Tolerance for floating-point line-fit comparisons.
const double _lineFitEpsilon = 0.005;

// Engine profile defaults (no browser-specific profile lookup).
const bool _preferPrefixWidthsForBreakableRuns = false;
const bool _preferEarlySoftHyphenBreak = false;

/// Internal line result with start/end segment/grapheme indices and width.
class InternalLayoutLine {
  const InternalLayoutLine({
    required this.startSegmentIndex,
    required this.startGraphemeIndex,
    required this.endSegmentIndex,
    required this.endGraphemeIndex,
    required this.width,
  });

  final int startSegmentIndex;
  final int startGraphemeIndex;
  final int endSegmentIndex;
  final int endGraphemeIndex;
  final double width;
}

bool _canBreakAfter(SegmentBreakKind kind) {
  return kind == SegmentBreakKind.space ||
      kind == SegmentBreakKind.preservedSpace ||
      kind == SegmentBreakKind.tab ||
      kind == SegmentBreakKind.zeroWidthBreak ||
      kind == SegmentBreakKind.softHyphen;
}

bool _isSimpleCollapsibleSpace(SegmentBreakKind kind) {
  return kind == SegmentBreakKind.space;
}

double _getTabAdvance(double lineWidth, double tabStopAdvance) {
  if (tabStopAdvance <= 0) return 0;
  final remainder = lineWidth % tabStopAdvance;
  if (remainder.abs() <= 1e-6) return tabStopAdvance;
  return tabStopAdvance - remainder;
}

double _getBreakableAdvance(
  List<double> graphemeWidths,
  List<double>? graphemePrefixWidths,
  int graphemeIndex,
  bool preferPrefixWidths,
) {
  if (!preferPrefixWidths || graphemePrefixWidths == null) {
    return graphemeWidths[graphemeIndex];
  }
  return graphemePrefixWidths[graphemeIndex] -
      (graphemeIndex > 0 ? graphemePrefixWidths[graphemeIndex - 1] : 0.0);
}

({int fitCount, double fittedWidth}) _fitSoftHyphenBreak(
  List<double> graphemeWidths,
  double initialWidth,
  double maxWidth,
  double discretionaryHyphenWidth,
  bool cumulativeWidths,
) {
  int fitCount = 0;
  double fittedWidth = initialWidth;

  while (fitCount < graphemeWidths.length) {
    final double nextWidth = cumulativeWidths
        ? initialWidth + graphemeWidths[fitCount]
        : fittedWidth + graphemeWidths[fitCount];
    final double nextLineWidth = fitCount + 1 < graphemeWidths.length
        ? nextWidth + discretionaryHyphenWidth
        : nextWidth;
    if (nextLineWidth > maxWidth + _lineFitEpsilon) break;
    fittedWidth = nextWidth;
    fitCount++;
  }

  return (fitCount: fitCount, fittedWidth: fittedWidth);
}

int _findChunkIndexForStart(PreparedCore prepared, int segmentIndex) {
  for (int i = 0; i < prepared.chunks.length; i++) {
    final chunk = prepared.chunks[i];
    if (segmentIndex < chunk.consumedEndSegmentIndex) return i;
  }
  return -1;
}

/// Skip leading spaces/breaks and return normalized cursor, or null if exhausted.
LayoutCursor? normalizeLineStart(PreparedCore prepared, LayoutCursor start) {
  int segmentIndex = start.segmentIndex;
  final int graphemeIndex = start.graphemeIndex;

  if (segmentIndex >= prepared.widths.length) return null;
  if (graphemeIndex > 0) return start;

  final int chunkIndex = _findChunkIndexForStart(prepared, segmentIndex);
  if (chunkIndex < 0) return null;

  final chunk = prepared.chunks[chunkIndex];
  if (chunk.startSegmentIndex == chunk.endSegmentIndex &&
      segmentIndex == chunk.startSegmentIndex) {
    return LayoutCursor(segmentIndex: segmentIndex, graphemeIndex: 0);
  }

  if (segmentIndex < chunk.startSegmentIndex) {
    segmentIndex = chunk.startSegmentIndex;
  }
  while (segmentIndex < chunk.endSegmentIndex) {
    final kind = prepared.kinds[segmentIndex];
    if (kind != SegmentBreakKind.space &&
        kind != SegmentBreakKind.zeroWidthBreak &&
        kind != SegmentBreakKind.softHyphen) {
      return LayoutCursor(segmentIndex: segmentIndex, graphemeIndex: 0);
    }
    segmentIndex++;
  }

  if (chunk.consumedEndSegmentIndex >= prepared.widths.length) return null;
  return LayoutCursor(
      segmentIndex: chunk.consumedEndSegmentIndex, graphemeIndex: 0);
}

/// Fast-path entry point: delegates to simple or full walker.
int countPreparedLines(PreparedCore prepared, double maxWidth) {
  if (prepared.simpleLineWalkFastPath) {
    return _countPreparedLinesSimple(prepared, maxWidth);
  }
  return walkPreparedLines(prepared, maxWidth);
}

int _countPreparedLinesSimple(PreparedCore prepared, double maxWidth) {
  final widths = prepared.widths;
  final kinds = prepared.kinds;
  final breakableWidths = prepared.breakableWidths;
  final breakablePrefixWidths = prepared.breakablePrefixWidths;

  if (widths.isEmpty) return 0;

  int lineCount = 0;
  double lineW = 0;
  bool hasContent = false;

  void placeOnFreshLine(int segmentIndex) {
    final double w = widths[segmentIndex];
    if (w > maxWidth && breakableWidths[segmentIndex] != null) {
      final gWidths = breakableWidths[segmentIndex]!;
      final gPrefixWidths = breakablePrefixWidths[segmentIndex];
      lineW = 0;
      for (int g = 0; g < gWidths.length; g++) {
        final double gw = _getBreakableAdvance(
          gWidths,
          gPrefixWidths,
          g,
          _preferPrefixWidthsForBreakableRuns,
        );
        if (lineW > 0 && lineW + gw > maxWidth + _lineFitEpsilon) {
          lineCount++;
          lineW = gw;
        } else {
          if (lineW == 0) lineCount++;
          lineW += gw;
        }
      }
    } else {
      lineW = w;
      lineCount++;
    }
    hasContent = true;
  }

  for (int i = 0; i < widths.length; i++) {
    final double w = widths[i];
    final kind = kinds[i];

    if (!hasContent) {
      placeOnFreshLine(i);
      continue;
    }

    final double newW = lineW + w;
    if (newW > maxWidth + _lineFitEpsilon) {
      if (_isSimpleCollapsibleSpace(kind)) continue;
      lineW = 0;
      hasContent = false;
      placeOnFreshLine(i);
      continue;
    }

    lineW = newW;
  }

  if (!hasContent) return lineCount + 1;
  return lineCount;
}

int _walkPreparedLinesSimple(
  PreparedCore prepared,
  double maxWidth,
  void Function(InternalLayoutLine)? onLine,
) {
  final widths = prepared.widths;
  final kinds = prepared.kinds;
  final breakableWidths = prepared.breakableWidths;
  final breakablePrefixWidths = prepared.breakablePrefixWidths;

  if (widths.isEmpty) return 0;

  int lineCount = 0;
  double lineW = 0;
  bool hasContent = false;
  int lineStartSegmentIndex = 0;
  int lineStartGraphemeIndex = 0;
  int lineEndSegmentIndex = 0;
  int lineEndGraphemeIndex = 0;
  int pendingBreakSegmentIndex = -1;
  double pendingBreakPaintWidth = 0;

  void clearPendingBreak() {
    pendingBreakSegmentIndex = -1;
    pendingBreakPaintWidth = 0;
  }

  void emitCurrentLine([
    int? endSegIdx,
    int? endGrIdx,
    double? w,
  ]) {
    final int esi = endSegIdx ?? lineEndSegmentIndex;
    final int egi = endGrIdx ?? lineEndGraphemeIndex;
    final double lw = w ?? lineW;
    lineCount++;
    onLine?.call(InternalLayoutLine(
      startSegmentIndex: lineStartSegmentIndex,
      startGraphemeIndex: lineStartGraphemeIndex,
      endSegmentIndex: esi,
      endGraphemeIndex: egi,
      width: lw,
    ));
    lineW = 0;
    hasContent = false;
    clearPendingBreak();
  }

  void startLineAtSegment(int segmentIndex, double width) {
    hasContent = true;
    lineStartSegmentIndex = segmentIndex;
    lineStartGraphemeIndex = 0;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
    lineW = width;
  }

  void startLineAtGrapheme(int segmentIndex, int graphemeIndex, double width) {
    hasContent = true;
    lineStartSegmentIndex = segmentIndex;
    lineStartGraphemeIndex = graphemeIndex;
    lineEndSegmentIndex = segmentIndex;
    lineEndGraphemeIndex = graphemeIndex + 1;
    lineW = width;
  }

  void appendWholeSegment(int segmentIndex, double width) {
    if (!hasContent) {
      startLineAtSegment(segmentIndex, width);
      return;
    }
    lineW += width;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
  }

  void updatePendingBreak(int segmentIndex, double segmentWidth) {
    if (!_canBreakAfter(kinds[segmentIndex])) return;
    pendingBreakSegmentIndex = segmentIndex + 1;
    pendingBreakPaintWidth = lineW - segmentWidth;
  }

  void appendBreakableSegmentFrom(int segmentIndex, int startGraphemeIndex) {
    final gWidths = breakableWidths[segmentIndex]!;
    final gPrefixWidths = breakablePrefixWidths[segmentIndex];
    for (int g = startGraphemeIndex; g < gWidths.length; g++) {
      final double gw = _getBreakableAdvance(
        gWidths,
        gPrefixWidths,
        g,
        _preferPrefixWidthsForBreakableRuns,
      );

      if (!hasContent) {
        startLineAtGrapheme(segmentIndex, g, gw);
        continue;
      }

      if (lineW + gw > maxWidth + _lineFitEpsilon) {
        emitCurrentLine();
        startLineAtGrapheme(segmentIndex, g, gw);
      } else {
        lineW += gw;
        lineEndSegmentIndex = segmentIndex;
        lineEndGraphemeIndex = g + 1;
      }
    }

    if (hasContent &&
        lineEndSegmentIndex == segmentIndex &&
        lineEndGraphemeIndex == gWidths.length) {
      lineEndSegmentIndex = segmentIndex + 1;
      lineEndGraphemeIndex = 0;
    }
  }

  void appendBreakableSegment(int segmentIndex) {
    appendBreakableSegmentFrom(segmentIndex, 0);
  }

  int i = 0;
  while (i < widths.length) {
    final double w = widths[i];
    final kind = kinds[i];

    if (!hasContent) {
      if (w > maxWidth && breakableWidths[i] != null) {
        appendBreakableSegment(i);
      } else {
        startLineAtSegment(i, w);
      }
      updatePendingBreak(i, w);
      i++;
      continue;
    }

    final double newW = lineW + w;
    if (newW > maxWidth + _lineFitEpsilon) {
      if (_canBreakAfter(kind)) {
        appendWholeSegment(i, w);
        emitCurrentLine(i + 1, 0, lineW - w);
        i++;
        continue;
      }

      if (pendingBreakSegmentIndex >= 0) {
        emitCurrentLine(pendingBreakSegmentIndex, 0, pendingBreakPaintWidth);
        continue;
      }

      if (w > maxWidth && breakableWidths[i] != null) {
        emitCurrentLine();
        appendBreakableSegment(i);
        i++;
        continue;
      }

      emitCurrentLine();
      continue;
    }

    appendWholeSegment(i, w);
    updatePendingBreak(i, w);
    i++;
  }

  if (hasContent) emitCurrentLine();
  return lineCount;
}

/// Full walker with line emission (simple + full paths).
int walkPreparedLines(
  PreparedCore prepared,
  double maxWidth, [
  void Function(InternalLayoutLine)? onLine,
]) {
  if (prepared.simpleLineWalkFastPath) {
    return _walkPreparedLinesSimple(prepared, maxWidth, onLine);
  }

  final widths = prepared.widths;
  final lineEndFitAdvances = prepared.lineEndFitAdvances;
  final lineEndPaintAdvances = prepared.lineEndPaintAdvances;
  final kinds = prepared.kinds;
  final breakableWidths = prepared.breakableWidths;
  final breakablePrefixWidths = prepared.breakablePrefixWidths;
  final double discretionaryHyphenWidth = prepared.discretionaryHyphenWidth;
  final double tabStopAdvance = prepared.tabStopAdvance;
  final chunks = prepared.chunks;

  if (widths.isEmpty || chunks.isEmpty) return 0;

  int lineCount = 0;
  double lineW = 0;
  bool hasContent = false;
  int lineStartSegmentIndex = 0;
  int lineStartGraphemeIndex = 0;
  int lineEndSegmentIndex = 0;
  int lineEndGraphemeIndex = 0;
  int pendingBreakSegmentIndex = -1;
  double pendingBreakFitWidth = 0;
  double pendingBreakPaintWidth = 0;
  SegmentBreakKind? pendingBreakKind;

  void clearPendingBreak() {
    pendingBreakSegmentIndex = -1;
    pendingBreakFitWidth = 0;
    pendingBreakPaintWidth = 0;
    pendingBreakKind = null;
  }

  void emitCurrentLine([
    int? endSegIdx,
    int? endGrIdx,
    double? w,
  ]) {
    final int esi = endSegIdx ?? lineEndSegmentIndex;
    final int egi = endGrIdx ?? lineEndGraphemeIndex;
    final double lw = w ?? lineW;
    lineCount++;
    onLine?.call(InternalLayoutLine(
      startSegmentIndex: lineStartSegmentIndex,
      startGraphemeIndex: lineStartGraphemeIndex,
      endSegmentIndex: esi,
      endGraphemeIndex: egi,
      width: lw,
    ));
    lineW = 0;
    hasContent = false;
    clearPendingBreak();
  }

  void startLineAtSegment(int segmentIndex, double width) {
    hasContent = true;
    lineStartSegmentIndex = segmentIndex;
    lineStartGraphemeIndex = 0;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
    lineW = width;
  }

  void startLineAtGrapheme(int segmentIndex, int graphemeIndex, double width) {
    hasContent = true;
    lineStartSegmentIndex = segmentIndex;
    lineStartGraphemeIndex = graphemeIndex;
    lineEndSegmentIndex = segmentIndex;
    lineEndGraphemeIndex = graphemeIndex + 1;
    lineW = width;
  }

  void appendWholeSegment(int segmentIndex, double width) {
    if (!hasContent) {
      startLineAtSegment(segmentIndex, width);
      return;
    }
    lineW += width;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
  }

  void updatePendingBreakForWholeSegment(int segmentIndex, double segmentWidth) {
    if (!_canBreakAfter(kinds[segmentIndex])) return;
    final double fitAdvance = kinds[segmentIndex] == SegmentBreakKind.tab
        ? 0
        : lineEndFitAdvances[segmentIndex];
    final double paintAdvance = kinds[segmentIndex] == SegmentBreakKind.tab
        ? segmentWidth
        : lineEndPaintAdvances[segmentIndex];
    pendingBreakSegmentIndex = segmentIndex + 1;
    pendingBreakFitWidth = lineW - segmentWidth + fitAdvance;
    pendingBreakPaintWidth = lineW - segmentWidth + paintAdvance;
    pendingBreakKind = kinds[segmentIndex];
  }

  void appendBreakableSegmentFrom(int segmentIndex, int startGraphemeIndex) {
    final gWidths = breakableWidths[segmentIndex]!;
    final gPrefixWidths = breakablePrefixWidths[segmentIndex];
    for (int g = startGraphemeIndex; g < gWidths.length; g++) {
      final double gw = _getBreakableAdvance(
        gWidths,
        gPrefixWidths,
        g,
        _preferPrefixWidthsForBreakableRuns,
      );

      if (!hasContent) {
        startLineAtGrapheme(segmentIndex, g, gw);
        continue;
      }

      if (lineW + gw > maxWidth + _lineFitEpsilon) {
        emitCurrentLine();
        startLineAtGrapheme(segmentIndex, g, gw);
      } else {
        lineW += gw;
        lineEndSegmentIndex = segmentIndex;
        lineEndGraphemeIndex = g + 1;
      }
    }

    if (hasContent &&
        lineEndSegmentIndex == segmentIndex &&
        lineEndGraphemeIndex == gWidths.length) {
      lineEndSegmentIndex = segmentIndex + 1;
      lineEndGraphemeIndex = 0;
    }
  }

  void appendBreakableSegment(int segmentIndex) {
    appendBreakableSegmentFrom(segmentIndex, 0);
  }

  // Returns true if the soft-hyphen break was handled (may emit a line).
  bool continueSoftHyphenBreakableSegment(int segmentIndex) {
    if (pendingBreakKind != SegmentBreakKind.softHyphen) return false;
    final gWidths = breakableWidths[segmentIndex];
    if (gWidths == null) return false;

    final List<double> fitWidths = _preferPrefixWidthsForBreakableRuns
        ? (breakablePrefixWidths[segmentIndex] ?? gWidths)
        : gWidths;
    final bool usesPrefixWidths = !identical(fitWidths, gWidths);
    final result = _fitSoftHyphenBreak(
      fitWidths,
      lineW,
      maxWidth,
      discretionaryHyphenWidth,
      usesPrefixWidths,
    );
    final int fitCount = result.fitCount;
    final double fittedWidth = result.fittedWidth;

    if (fitCount == 0) return false;

    lineW = fittedWidth;
    lineEndSegmentIndex = segmentIndex;
    lineEndGraphemeIndex = fitCount;
    clearPendingBreak();

    if (fitCount == gWidths.length) {
      lineEndSegmentIndex = segmentIndex + 1;
      lineEndGraphemeIndex = 0;
      return true;
    }

    emitCurrentLine(
      segmentIndex,
      fitCount,
      fittedWidth + discretionaryHyphenWidth,
    );
    appendBreakableSegmentFrom(segmentIndex, fitCount);
    return true;
  }

  void emitEmptyChunk(PreparedLineChunk chunk) {
    lineCount++;
    onLine?.call(InternalLayoutLine(
      startSegmentIndex: chunk.startSegmentIndex,
      startGraphemeIndex: 0,
      endSegmentIndex: chunk.consumedEndSegmentIndex,
      endGraphemeIndex: 0,
      width: 0,
    ));
    clearPendingBreak();
  }

  for (int chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
    final chunk = chunks[chunkIndex];
    if (chunk.startSegmentIndex == chunk.endSegmentIndex) {
      emitEmptyChunk(chunk);
      continue;
    }

    hasContent = false;
    lineW = 0;
    lineStartSegmentIndex = chunk.startSegmentIndex;
    lineStartGraphemeIndex = 0;
    lineEndSegmentIndex = chunk.startSegmentIndex;
    lineEndGraphemeIndex = 0;
    clearPendingBreak();

    int i = chunk.startSegmentIndex;
    while (i < chunk.endSegmentIndex) {
      final kind = kinds[i];
      final double w =
          kind == SegmentBreakKind.tab ? _getTabAdvance(lineW, tabStopAdvance) : widths[i];

      if (kind == SegmentBreakKind.softHyphen) {
        if (hasContent) {
          lineEndSegmentIndex = i + 1;
          lineEndGraphemeIndex = 0;
          pendingBreakSegmentIndex = i + 1;
          pendingBreakFitWidth = lineW + discretionaryHyphenWidth;
          pendingBreakPaintWidth = lineW + discretionaryHyphenWidth;
          pendingBreakKind = kind;
        }
        i++;
        continue;
      }

      if (!hasContent) {
        if (w > maxWidth && breakableWidths[i] != null) {
          appendBreakableSegment(i);
        } else {
          startLineAtSegment(i, w);
        }
        updatePendingBreakForWholeSegment(i, w);
        i++;
        continue;
      }

      final double newW = lineW + w;
      if (newW > maxWidth + _lineFitEpsilon) {
        final double currentBreakFitWidth =
            lineW + (kind == SegmentBreakKind.tab ? 0 : lineEndFitAdvances[i]);
        final double currentBreakPaintWidth =
            lineW + (kind == SegmentBreakKind.tab ? w : lineEndPaintAdvances[i]);

        if (pendingBreakKind == SegmentBreakKind.softHyphen &&
            _preferEarlySoftHyphenBreak &&
            pendingBreakFitWidth <= maxWidth + _lineFitEpsilon) {
          emitCurrentLine(pendingBreakSegmentIndex, 0, pendingBreakPaintWidth);
          continue;
        }

        if (pendingBreakKind == SegmentBreakKind.softHyphen &&
            continueSoftHyphenBreakableSegment(i)) {
          i++;
          continue;
        }

        if (_canBreakAfter(kind) &&
            currentBreakFitWidth <= maxWidth + _lineFitEpsilon) {
          appendWholeSegment(i, w);
          emitCurrentLine(i + 1, 0, currentBreakPaintWidth);
          i++;
          continue;
        }

        if (pendingBreakSegmentIndex >= 0 &&
            pendingBreakFitWidth <= maxWidth + _lineFitEpsilon) {
          emitCurrentLine(pendingBreakSegmentIndex, 0, pendingBreakPaintWidth);
          continue;
        }

        if (w > maxWidth && breakableWidths[i] != null) {
          emitCurrentLine();
          appendBreakableSegment(i);
          i++;
          continue;
        }

        emitCurrentLine();
        continue;
      }

      appendWholeSegment(i, w);
      updatePendingBreakForWholeSegment(i, w);
      i++;
    }

    if (hasContent) {
      final double finalPaintWidth =
          pendingBreakSegmentIndex == chunk.consumedEndSegmentIndex
              ? pendingBreakPaintWidth
              : lineW;
      emitCurrentLine(chunk.consumedEndSegmentIndex, 0, finalPaintWidth);
    }
  }

  return lineCount;
}

/// Iterator-style single-line layout.
InternalLayoutLine? layoutNextLineRange(
  PreparedCore prepared,
  LayoutCursor start,
  double maxWidth,
) {
  final normalizedStart = normalizeLineStart(prepared, start);
  if (normalizedStart == null) return null;

  if (prepared.simpleLineWalkFastPath) {
    return _layoutNextLineRangeSimple(prepared, normalizedStart, maxWidth);
  }

  final int chunkIndex =
      _findChunkIndexForStart(prepared, normalizedStart.segmentIndex);
  if (chunkIndex < 0) return null;

  final chunk = prepared.chunks[chunkIndex];
  if (chunk.startSegmentIndex == chunk.endSegmentIndex) {
    return InternalLayoutLine(
      startSegmentIndex: chunk.startSegmentIndex,
      startGraphemeIndex: 0,
      endSegmentIndex: chunk.consumedEndSegmentIndex,
      endGraphemeIndex: 0,
      width: 0,
    );
  }

  final widths = prepared.widths;
  final lineEndFitAdvances = prepared.lineEndFitAdvances;
  final lineEndPaintAdvances = prepared.lineEndPaintAdvances;
  final kinds = prepared.kinds;
  final breakableWidths = prepared.breakableWidths;
  final breakablePrefixWidths = prepared.breakablePrefixWidths;
  final double discretionaryHyphenWidth = prepared.discretionaryHyphenWidth;
  final double tabStopAdvance = prepared.tabStopAdvance;

  double lineW = 0;
  bool hasContent = false;
  final int lineStartSegmentIndex = normalizedStart.segmentIndex;
  final int lineStartGraphemeIndex = normalizedStart.graphemeIndex;
  int lineEndSegmentIndex = lineStartSegmentIndex;
  int lineEndGraphemeIndex = lineStartGraphemeIndex;
  int pendingBreakSegmentIndex = -1;
  double pendingBreakFitWidth = 0;
  double pendingBreakPaintWidth = 0;
  SegmentBreakKind? pendingBreakKind;

  void clearPendingBreak() {
    pendingBreakSegmentIndex = -1;
    pendingBreakFitWidth = 0;
    pendingBreakPaintWidth = 0;
    pendingBreakKind = null;
  }

  InternalLayoutLine? finishLine([
    int? endSegIdx,
    int? endGrIdx,
    double? w,
  ]) {
    if (!hasContent) return null;
    return InternalLayoutLine(
      startSegmentIndex: lineStartSegmentIndex,
      startGraphemeIndex: lineStartGraphemeIndex,
      endSegmentIndex: endSegIdx ?? lineEndSegmentIndex,
      endGraphemeIndex: endGrIdx ?? lineEndGraphemeIndex,
      width: w ?? lineW,
    );
  }

  void startLineAtSegment(int segmentIndex, double width) {
    hasContent = true;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
    lineW = width;
  }

  void startLineAtGrapheme(int segmentIndex, int graphemeIndex, double width) {
    hasContent = true;
    lineEndSegmentIndex = segmentIndex;
    lineEndGraphemeIndex = graphemeIndex + 1;
    lineW = width;
  }

  void appendWholeSegment(int segmentIndex, double width) {
    if (!hasContent) {
      startLineAtSegment(segmentIndex, width);
      return;
    }
    lineW += width;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
  }

  void updatePendingBreakForWholeSegment(int segmentIndex, double segmentWidth) {
    if (!_canBreakAfter(kinds[segmentIndex])) return;
    final double fitAdvance = kinds[segmentIndex] == SegmentBreakKind.tab
        ? 0
        : lineEndFitAdvances[segmentIndex];
    final double paintAdvance = kinds[segmentIndex] == SegmentBreakKind.tab
        ? segmentWidth
        : lineEndPaintAdvances[segmentIndex];
    pendingBreakSegmentIndex = segmentIndex + 1;
    pendingBreakFitWidth = lineW - segmentWidth + fitAdvance;
    pendingBreakPaintWidth = lineW - segmentWidth + paintAdvance;
    pendingBreakKind = kinds[segmentIndex];
  }

  // Returns non-null if the current line should be returned immediately.
  InternalLayoutLine? appendBreakableSegmentFrom(
      int segmentIndex, int startGraphemeIndex) {
    final gWidths = breakableWidths[segmentIndex]!;
    final gPrefixWidths = breakablePrefixWidths[segmentIndex];
    for (int g = startGraphemeIndex; g < gWidths.length; g++) {
      final double gw = _getBreakableAdvance(
        gWidths,
        gPrefixWidths,
        g,
        _preferPrefixWidthsForBreakableRuns,
      );

      if (!hasContent) {
        startLineAtGrapheme(segmentIndex, g, gw);
        continue;
      }

      if (lineW + gw > maxWidth + _lineFitEpsilon) {
        return finishLine();
      }

      lineW += gw;
      lineEndSegmentIndex = segmentIndex;
      lineEndGraphemeIndex = g + 1;
    }

    if (hasContent &&
        lineEndSegmentIndex == segmentIndex &&
        lineEndGraphemeIndex == gWidths.length) {
      lineEndSegmentIndex = segmentIndex + 1;
      lineEndGraphemeIndex = 0;
    }
    return null;
  }

  InternalLayoutLine? maybeFinishAtSoftHyphen(int segmentIndex) {
    if (pendingBreakKind != SegmentBreakKind.softHyphen ||
        pendingBreakSegmentIndex < 0) {
      return null;
    }

    final gWidths = breakableWidths[segmentIndex];
    if (gWidths != null) {
      final List<double> fitWidths = _preferPrefixWidthsForBreakableRuns
          ? (breakablePrefixWidths[segmentIndex] ?? gWidths)
          : gWidths;
      final bool usesPrefixWidths = !identical(fitWidths, gWidths);
      final result = _fitSoftHyphenBreak(
        fitWidths,
        lineW,
        maxWidth,
        discretionaryHyphenWidth,
        usesPrefixWidths,
      );
      final int fitCount = result.fitCount;
      final double fittedWidth = result.fittedWidth;

      if (fitCount == gWidths.length) {
        lineW = fittedWidth;
        lineEndSegmentIndex = segmentIndex + 1;
        lineEndGraphemeIndex = 0;
        clearPendingBreak();
        return null;
      }

      if (fitCount > 0) {
        return finishLine(
          segmentIndex,
          fitCount,
          fittedWidth + discretionaryHyphenWidth,
        );
      }
    }

    if (pendingBreakFitWidth <= maxWidth + _lineFitEpsilon) {
      return finishLine(pendingBreakSegmentIndex, 0, pendingBreakPaintWidth);
    }

    return null;
  }

  for (int i = normalizedStart.segmentIndex; i < chunk.endSegmentIndex; i++) {
    final kind = kinds[i];
    final int startGraphemeIdx =
        i == normalizedStart.segmentIndex ? normalizedStart.graphemeIndex : 0;
    final double w = kind == SegmentBreakKind.tab
        ? _getTabAdvance(lineW, tabStopAdvance)
        : widths[i];

    if (kind == SegmentBreakKind.softHyphen && startGraphemeIdx == 0) {
      if (hasContent) {
        lineEndSegmentIndex = i + 1;
        lineEndGraphemeIndex = 0;
        pendingBreakSegmentIndex = i + 1;
        pendingBreakFitWidth = lineW + discretionaryHyphenWidth;
        pendingBreakPaintWidth = lineW + discretionaryHyphenWidth;
        pendingBreakKind = kind;
      }
      continue;
    }

    if (!hasContent) {
      if (startGraphemeIdx > 0) {
        final line = appendBreakableSegmentFrom(i, startGraphemeIdx);
        if (line != null) return line;
      } else if (w > maxWidth && breakableWidths[i] != null) {
        final line = appendBreakableSegmentFrom(i, 0);
        if (line != null) return line;
      } else {
        startLineAtSegment(i, w);
      }
      updatePendingBreakForWholeSegment(i, w);
      continue;
    }

    final double newW = lineW + w;
    if (newW > maxWidth + _lineFitEpsilon) {
      final double currentBreakFitWidth =
          lineW + (kind == SegmentBreakKind.tab ? 0 : lineEndFitAdvances[i]);
      final double currentBreakPaintWidth =
          lineW + (kind == SegmentBreakKind.tab ? w : lineEndPaintAdvances[i]);

      if (pendingBreakKind == SegmentBreakKind.softHyphen &&
          _preferEarlySoftHyphenBreak &&
          pendingBreakFitWidth <= maxWidth + _lineFitEpsilon) {
        return finishLine(pendingBreakSegmentIndex, 0, pendingBreakPaintWidth);
      }

      final softBreakLine = maybeFinishAtSoftHyphen(i);
      if (softBreakLine != null) return softBreakLine;

      if (_canBreakAfter(kind) &&
          currentBreakFitWidth <= maxWidth + _lineFitEpsilon) {
        appendWholeSegment(i, w);
        return finishLine(i + 1, 0, currentBreakPaintWidth);
      }

      if (pendingBreakSegmentIndex >= 0 &&
          pendingBreakFitWidth <= maxWidth + _lineFitEpsilon) {
        return finishLine(pendingBreakSegmentIndex, 0, pendingBreakPaintWidth);
      }

      if (w > maxWidth && breakableWidths[i] != null) {
        final currentLine = finishLine();
        if (currentLine != null) return currentLine;
        final line = appendBreakableSegmentFrom(i, 0);
        if (line != null) return line;
      }

      return finishLine();
    }

    appendWholeSegment(i, w);
    updatePendingBreakForWholeSegment(i, w);
  }

  if (pendingBreakSegmentIndex == chunk.consumedEndSegmentIndex &&
      lineEndGraphemeIndex == 0) {
    return finishLine(
        chunk.consumedEndSegmentIndex, 0, pendingBreakPaintWidth);
  }

  return finishLine(chunk.consumedEndSegmentIndex, 0, lineW);
}

InternalLayoutLine? _layoutNextLineRangeSimple(
  PreparedCore prepared,
  LayoutCursor normalizedStart,
  double maxWidth,
) {
  final widths = prepared.widths;
  final kinds = prepared.kinds;
  final breakableWidths = prepared.breakableWidths;
  final breakablePrefixWidths = prepared.breakablePrefixWidths;

  double lineW = 0;
  bool hasContent = false;
  final int lineStartSegmentIndex = normalizedStart.segmentIndex;
  final int lineStartGraphemeIndex = normalizedStart.graphemeIndex;
  int lineEndSegmentIndex = lineStartSegmentIndex;
  int lineEndGraphemeIndex = lineStartGraphemeIndex;
  int pendingBreakSegmentIndex = -1;
  double pendingBreakPaintWidth = 0;

  InternalLayoutLine? finishLine([
    int? endSegIdx,
    int? endGrIdx,
    double? w,
  ]) {
    if (!hasContent) return null;
    return InternalLayoutLine(
      startSegmentIndex: lineStartSegmentIndex,
      startGraphemeIndex: lineStartGraphemeIndex,
      endSegmentIndex: endSegIdx ?? lineEndSegmentIndex,
      endGraphemeIndex: endGrIdx ?? lineEndGraphemeIndex,
      width: w ?? lineW,
    );
  }

  void startLineAtSegment(int segmentIndex, double width) {
    hasContent = true;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
    lineW = width;
  }

  void startLineAtGrapheme(int segmentIndex, int graphemeIndex, double width) {
    hasContent = true;
    lineEndSegmentIndex = segmentIndex;
    lineEndGraphemeIndex = graphemeIndex + 1;
    lineW = width;
  }

  void appendWholeSegment(int segmentIndex, double width) {
    if (!hasContent) {
      startLineAtSegment(segmentIndex, width);
      return;
    }
    lineW += width;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
  }

  void updatePendingBreak(int segmentIndex, double segmentWidth) {
    if (!_canBreakAfter(kinds[segmentIndex])) return;
    pendingBreakSegmentIndex = segmentIndex + 1;
    pendingBreakPaintWidth = lineW - segmentWidth;
  }

  InternalLayoutLine? appendBreakableSegmentFrom(
      int segmentIndex, int startGraphemeIndex) {
    final gWidths = breakableWidths[segmentIndex]!;
    final gPrefixWidths = breakablePrefixWidths[segmentIndex];
    for (int g = startGraphemeIndex; g < gWidths.length; g++) {
      final double gw = _getBreakableAdvance(
        gWidths,
        gPrefixWidths,
        g,
        _preferPrefixWidthsForBreakableRuns,
      );

      if (!hasContent) {
        startLineAtGrapheme(segmentIndex, g, gw);
        continue;
      }

      if (lineW + gw > maxWidth + _lineFitEpsilon) {
        return finishLine();
      }

      lineW += gw;
      lineEndSegmentIndex = segmentIndex;
      lineEndGraphemeIndex = g + 1;
    }

    if (hasContent &&
        lineEndSegmentIndex == segmentIndex &&
        lineEndGraphemeIndex == gWidths.length) {
      lineEndSegmentIndex = segmentIndex + 1;
      lineEndGraphemeIndex = 0;
    }
    return null;
  }

  for (int i = normalizedStart.segmentIndex; i < widths.length; i++) {
    final double w = widths[i];
    final kind = kinds[i];
    final int startGraphemeIdx =
        i == normalizedStart.segmentIndex ? normalizedStart.graphemeIndex : 0;

    if (!hasContent) {
      if (startGraphemeIdx > 0) {
        final line = appendBreakableSegmentFrom(i, startGraphemeIdx);
        if (line != null) return line;
      } else if (w > maxWidth && breakableWidths[i] != null) {
        final line = appendBreakableSegmentFrom(i, 0);
        if (line != null) return line;
      } else {
        startLineAtSegment(i, w);
      }
      updatePendingBreak(i, w);
      continue;
    }

    final double newW = lineW + w;
    if (newW > maxWidth + _lineFitEpsilon) {
      if (_canBreakAfter(kind)) {
        appendWholeSegment(i, w);
        return finishLine(i + 1, 0, lineW - w);
      }

      if (pendingBreakSegmentIndex >= 0) {
        return finishLine(pendingBreakSegmentIndex, 0, pendingBreakPaintWidth);
      }

      if (w > maxWidth && breakableWidths[i] != null) {
        final currentLine = finishLine();
        if (currentLine != null) return currentLine;
        final line = appendBreakableSegmentFrom(i, 0);
        if (line != null) return line;
      }

      return finishLine();
    }

    appendWholeSegment(i, w);
    updatePendingBreak(i, w);
  }

  return finishLine();
}
