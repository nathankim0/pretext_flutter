import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pretext_flutter/pretext_flutter.dart';

const String kFlutterLogoAscii = r'''
                                              ...--------------------..
                                            ...:-------------------..
                                          ...:-------------------:..
                                        ...:-------------------:...
                                       ...--------------------..
                                     ...--------------------..
                                   ...--------------------...
                                 ...:-------------------:..
                               ...:-------------------:..
                              ..:-------------------:...
                            ...--------------------...
                          ...--------------------...
                        ...:-------------------...
                       ..:-------------------:...
                     ..:-------------------:..
                   ..:-------------------:...    ......................
                 ...--------------------....   ...--------------------..
                 .:-------------------.       ..--------------------...
                  .:----------------:.      ..--------------------:..
                   ..:------------:.      ..:-------------------:...
                      .:---------...    ..:=-------------------..
                        .------...     .:=====---------------...
                         ..--..      ..=========-----------...
                          ...      ..-============-------:...
                                 ..-================---:...
                               ..:===================:...
                               ...-================+##-..
                                 ...-============+*####*-..
                                   ..:=========+*########+:..
                                     ..:=====+*############+..
                                       ..:==*################+...
                                        ...=###################=...
                                          ...+##################*-..
                                            ..:*##################*:.
                                              ..:*##################*...
                                               ...::::::::::::::::::::..
''';

const String kFlutterLogoText =
    'Flutter is Google\'s UI toolkit for building beautiful apps. '
    'pretext_flutter measures once, lays out everywhere, and keeps text fluid at 60fps. '
    'Pure arithmetic text layout. '
    'Real-time reflow around moving geometry. '
    'Built by Nathan Kim. ';

const Color kFlutterLogoLightBlue = Color(0xFF54C5F8);
const Color kFlutterLogoMediumBlue = Color(0xFF29B6F6);
const Color kFlutterLogoDarkBlue = Color(0xFF01579B);

final FlutterTextLogoMask kFlutterTextLogoMask =
    FlutterTextLogoMask.fromAscii(kFlutterLogoAscii);

class FlutterTextLogoPaintLine {
  const FlutterTextLogoPaintLine({
    required this.text,
    required this.x,
    required this.y,
    required this.color,
  });

  final String text;
  final double x;
  final double y;
  final Color color;
}

class FlutterTextLogoObstacle {
  const FlutterTextLogoObstacle({
    required this.mask,
    required this.rect,
    required this.lineHeight,
  });

  final FlutterTextLogoMask mask;
  final Rect rect;
  final double lineHeight;

  List<(double, double)> intervalsForBand(double bandTop, double bandBottom) {
    return mask.intervalsForBand(
      bandTop: bandTop,
      bandBottom: bandBottom,
      rect: rect,
    );
  }

  List<FlutterTextLogoPaintLine> layoutText(
    PreparedTextWithSegments prepared,
  ) {
    final lines = <FlutterTextLogoPaintLine>[];
    var cursor = const LayoutCursor(segmentIndex: 0, graphemeIndex: 0);

    for (final row in mask.rows) {
      final y = rect.top + row.top * rect.height;

      for (final segment in row.segments) {
        final x = rect.left + segment.left * rect.width;
        final width = (segment.right - segment.left) * rect.width;
        if (width < 10) continue;

        final line = layoutNextLine(prepared, cursor, width) ??
            layoutNextLine(
              prepared,
              const LayoutCursor(segmentIndex: 0, graphemeIndex: 0),
              width,
            );
        if (line == null) continue;

        lines.add(FlutterTextLogoPaintLine(
          text: line.text,
          x: x,
          y: y,
          color: _toneColor(segment.tone),
        ));
        cursor = line.end;
      }
    }

    return lines;
  }

  static Color _toneColor(int tone) {
    switch (tone) {
      case 0:
        return kFlutterLogoLightBlue;
      case 1:
        return kFlutterLogoMediumBlue;
      default:
        return kFlutterLogoDarkBlue;
    }
  }
}

class FlutterTextLogoMask {
  FlutterTextLogoMask._({
    required this.rows,
    required this.aspectRatio,
  });

  factory FlutterTextLogoMask.fromAscii(String ascii) {
    final rawLines = ascii
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+$'), ''))
        .where((line) => line.trim().isNotEmpty)
        .toList();

    var minCol = 1 << 30;
    var maxCol = -1;

    for (final line in rawLines) {
      for (var i = 0; i < line.length; i++) {
        if (_toneFor(line[i]) == null) continue;
        minCol = math.min(minCol, i);
        maxCol = math.max(maxCol, i);
      }
    }

    final rowCount = rawLines.length;
    final colCount = maxCol - minCol + 1;
    final rows = <FlutterTextLogoRow>[];

    for (var rowIndex = 0; rowIndex < rawLines.length; rowIndex++) {
      final line = rawLines[rowIndex];
      final segments = <FlutterTextLogoSegment>[];
      int? currentTone;
      var runStart = -1;

      for (var col = minCol; col <= maxCol + 1; col++) {
        final tone =
            col <= maxCol && col < line.length ? _toneFor(line[col]) : null;
        if (tone == currentTone) continue;

        if (currentTone != null && runStart != -1) {
          segments.add(FlutterTextLogoSegment(
            left: (runStart - minCol) / colCount,
            right: (col - minCol) / colCount,
            tone: currentTone,
          ));
        }

        currentTone = tone;
        runStart = tone == null ? -1 : col;
      }

      rows.add(FlutterTextLogoRow(
        top: rowIndex / rowCount,
        bottom: (rowIndex + 1) / rowCount,
        segments: segments,
      ));
    }

    return FlutterTextLogoMask._(
      rows: rows,
      aspectRatio: colCount / rowCount,
    );
  }

  final List<FlutterTextLogoRow> rows;
  final double aspectRatio;

  List<(double, double)> intervalsForBand({
    required double bandTop,
    required double bandBottom,
    required Rect rect,
  }) {
    final intervals = <(double, double)>[];

    for (final row in rows) {
      final rowTop = rect.top + row.top * rect.height;
      final rowBottom = rect.top + row.bottom * rect.height;
      if (bandBottom <= rowTop || bandTop >= rowBottom) continue;

      for (final segment in row.segments) {
        intervals.add((
          rect.left + segment.left * rect.width,
          rect.left + segment.right * rect.width,
        ));
      }
    }

    return _mergeIntervals(intervals);
  }

  static List<(double, double)> _mergeIntervals(
    List<(double, double)> intervals,
  ) {
    if (intervals.isEmpty) return const [];
    final sorted = List<(double, double)>.from(intervals)
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(double, double)>[sorted.first];

    for (var i = 1; i < sorted.length; i++) {
      final current = sorted[i];
      final last = merged.last;
      if (current.$1 <= last.$2 + 1) {
        merged[merged.length - 1] = (
          last.$1,
          math.max(last.$2, current.$2),
        );
      } else {
        merged.add(current);
      }
    }

    return merged;
  }

  static int? _toneFor(String char) {
    switch (char) {
      case '.':
      case '-':
      case ':':
        return 0;
      case '=':
      case '+':
        return 1;
      case '*':
      case '#':
        return 2;
      default:
        return null;
    }
  }
}

class FlutterTextLogoRow {
  const FlutterTextLogoRow({
    required this.top,
    required this.bottom,
    required this.segments,
  });

  final double top;
  final double bottom;
  final List<FlutterTextLogoSegment> segments;
}

class FlutterTextLogoSegment {
  const FlutterTextLogoSegment({
    required this.left,
    required this.right,
    required this.tone,
  });

  final double left;
  final double right;
  final int tone;
}
