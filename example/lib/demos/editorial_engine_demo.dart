import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pretext_flutter/pretext_flutter.dart';

import 'flutter_text_logo_mask.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kBodyFontSize = 16.0;
const _kBodyLineHeight = 28.0;
const _kHeadlineText = 'THE FUTURE OF TEXT LAYOUT IS NOT CSS';
const _kGutter = 40.0;
const _kColGap = 36.0;
const _kBottomGap = 20.0;
const _kDropCapLines = 3;
const _kMinSlotWidth = 50.0;
const _kOrbHPad = 14.0;
const _kOrbVPad = 4.0;
const _kOrbSeparationGap = 20.0;
const _kMaxContentWidth = 1400.0;
const _kNarrowBreakpoint = 760.0;
const _kNarrowGutter = 20.0;
const _kNarrowColGap = 20.0;
const _kNarrowBottomGap = 16.0;
const _kNarrowOrbScale = 0.58;
const _kNarrowActiveOrbs = 3;
const _kMaxDt = 0.05;
const _kSeparationForce = 0.8;
const _kDragTapThreshold = 16.0; // squared distance
const _kLogoFontSize = 4.5;
const _kLogoLineHeight = 4.5;
const _kLogoPadding = 18.0;
const _kLogoBodyGap = 20.0;

const _kBackgroundColor = Color(0xFF12122A);
const _kTextColor = Color(0xFFF0EDE6);
const _kDividerColor = Color(0x22FFFFFF);
const _kPullquoteBorderColor = Color(0x44FFFFFF);

const _kBodyText = 'The web renders text through a pipeline designed thirty '
    'years ago for static documents. A browser loads a font, shapes text into '
    'glyphs, measures their combined width, determines where lines break, and '
    'positions each line vertically. Every step depends on the previous one.\n\n'
    'For a paragraph in a blog post, this pipeline is invisible. But the web '
    'is no longer a collection of static documents. It is a platform for '
    'applications that need to know about text in ways the original pipeline '
    'never anticipated.\n\n'
    'A messaging application needs the exact height of every message bubble '
    'before rendering a virtualized list. A masonry layout needs the height of '
    'every card. An editorial page needs text to flow around images and '
    'interactive elements. A responsive dashboard needs to resize text in real '
    'time.\n\n'
    'Every one of these operations requires text measurement. And every '
    'measurement on the web today triggers a synchronous layout reflow. The '
    'cost is devastating. Measuring a single text block forces the browser to '
    'recalculate every element on the page.\n\n'
    'Flutter changes this equation entirely. With pretext_flutter, text '
    'segments are measured once and cached. Subsequent layouts at any width are '
    'pure arithmetic \u2014 no rendering engine involved. This demo shows text '
    'reflowing at 60 frames per second around moving obstacles, something that '
    'would cause catastrophic jank on the web.\n\n'
    'The circles you see are not CSS shapes or SVG clip paths. They are '
    'mathematical obstacles that the layout engine routes around line by line. '
    'Drag them. Watch the text follow. Every frame is a fresh layout pass, yet '
    'the cost is negligible because the expensive measurement happened only '
    'once.\n\n'
    'This is what text layout looks like when you remove the DOM from the '
    'equation. No reflow. No thrashing. No compromise. Just pure geometry '
    'flowing around arbitrary shapes at interactive speeds.';

const _kPullquoteText =
    '\u201CThe performance improvement is not incremental \u2014 it is '
    'categorical. 0.05ms versus 30ms. Zero reflows versus five hundred.\u201D';

// ---------------------------------------------------------------------------
// Interval helpers
// ---------------------------------------------------------------------------

class _Interval {
  const _Interval(this.left, this.right);
  final double left;
  final double right;
}

List<_Interval> _carveLineSlots(_Interval base, List<_Interval> blocked) {
  var slots = [base];
  for (final block in blocked) {
    final next = <_Interval>[];
    for (final slot in slots) {
      if (block.right <= slot.left || block.left >= slot.right) {
        next.add(slot);
        continue;
      }
      if (block.left > slot.left) {
        next.add(_Interval(slot.left, block.left));
      }
      if (block.right < slot.right) {
        next.add(_Interval(block.right, slot.right));
      }
    }
    slots = next;
  }
  return slots.where((s) => s.right - s.left >= _kMinSlotWidth).toList();
}

_Interval? _circleIntervalForBand(
  double cx,
  double cy,
  double r,
  double bandTop,
  double bandBottom,
) {
  final top = bandTop - _kOrbVPad;
  final bottom = bandBottom + _kOrbVPad;
  if (top >= cy + r || bottom <= cy - r) return null;
  final minDy = (cy >= top && cy <= bottom)
      ? 0.0
      : (cy < top ? top - cy : cy - bottom);
  if (minDy >= r) return null;
  final maxDx = sqrt(r * r - minDy * minDy);
  return _Interval(cx - maxDx - _kOrbHPad, cx + maxDx + _kOrbHPad);
}

// ---------------------------------------------------------------------------
// Positioned line (computed layout output)
// ---------------------------------------------------------------------------

class _PositionedLine {
  const _PositionedLine({
    required this.x,
    required this.y,
    required this.width,
    required this.text,
  });
  final double x;
  final double y;
  final double width;
  final String text;
}

// ---------------------------------------------------------------------------
// Orb model
// ---------------------------------------------------------------------------

class _OrbDef {
  const _OrbDef({
    required this.fx,
    required this.fy,
    required this.r,
    required this.vx,
    required this.vy,
    required this.color,
  });
  final double fx;
  final double fy;
  final double r;
  final double vx;
  final double vy;
  final Color color;
}

class _Orb {
  _Orb({
    required this.x,
    required this.y,
    required this.r,
    required this.vx,
    required this.vy,
    required this.color,
  });

  double x;
  double y;
  final double r;
  double vx;
  double vy;
  final Color color;
  bool paused = false;
}

const _kOrbDefs = [
  _OrbDef(fx: 0.52, fy: 0.22, r: 100, vx: 24, vy: 16, color: Color(0xFFC4A35A)),
  _OrbDef(fx: 0.18, fy: 0.48, r: 80, vx: -19, vy: 26, color: Color(0xFF648CFF)),
  _OrbDef(fx: 0.74, fy: 0.58, r: 90, vx: 16, vy: -21, color: Color(0xFFE86482)),
  _OrbDef(fx: 0.38, fy: 0.72, r: 70, vx: -26, vy: -14, color: Color(0xFF50C88C)),
  _OrbDef(fx: 0.86, fy: 0.18, r: 60, vx: -13, vy: 19, color: Color(0xFF9664DC)),
];

// ---------------------------------------------------------------------------
// Rect obstacle (pull quote box)
// ---------------------------------------------------------------------------

class _RectObstacle {
  const _RectObstacle(this.x, this.y, this.w, this.h);
  final double x;
  final double y;
  final double w;
  final double h;
}

class _FloatingLogo {
  _FloatingLogo({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
  });

  double x;
  double y;
  double vx;
  double vy;
  bool paused = false;
}

class _SceneMetrics {
  const _SceneMetrics({
    required this.isNarrow,
    required this.gutter,
    required this.colGap,
    required this.bottomGap,
    required this.orbScale,
    required this.activeOrbCount,
    required this.bodyTop,
    required this.bodyHeight,
    required this.columnCount,
    required this.columnWidth,
    required this.contentLeft,
    required this.contentWidth,
    required this.headlineFit,
  });

  final bool isNarrow;
  final double gutter;
  final double colGap;
  final double bottomGap;
  final double orbScale;
  final int activeOrbCount;
  final double bodyTop;
  final double bodyHeight;
  final int columnCount;
  final double columnWidth;
  final double contentLeft;
  final double contentWidth;
  final _HeadlineFit headlineFit;
}

_SceneMetrics _computeSceneMetrics(Size size) {
  final isNarrow = size.width < _kNarrowBreakpoint;
  final gutter = isNarrow ? _kNarrowGutter : _kGutter;
  final colGap = isNarrow ? _kNarrowColGap : _kColGap;
  final bottomGap = isNarrow ? _kNarrowBottomGap : _kBottomGap;
  final orbScale = isNarrow ? _kNarrowOrbScale : 1.0;
  final activeOrbCount =
      isNarrow ? min(_kNarrowActiveOrbs, _kOrbDefs.length) : _kOrbDefs.length;

  final headlineMaxWidth = min(size.width - gutter * 2, 1000.0);
  final headlineMaxHeight = size.height * (isNarrow ? 0.20 : 0.24);
  final headlineFit = _fitHeadline(
    headlineMaxWidth,
    headlineMaxHeight,
    isNarrow ? 32.0 : 80.0,
  );
  final headlineLineHeight =
      (headlineFit.fontSize * 0.93).roundToDouble();
  final headlineHeight = headlineFit.lines.length * headlineLineHeight;

  final bodyTop = gutter + headlineHeight + (isNarrow ? 14 : 20);
  final bodyHeight = size.height - bodyTop - bottomGap;
  final columnCount = size.width > 1000 ? 3 : (size.width > 640 ? 2 : 1);
  final totalGutter = gutter * 2 + colGap * (columnCount - 1);
  final maxContentWidth = min(size.width, _kMaxContentWidth);
  final columnWidth =
      ((maxContentWidth - totalGutter) / columnCount).floorToDouble();
  final contentWidth = columnCount * columnWidth + (columnCount - 1) * colGap;
  final contentLeft = ((size.width - contentWidth) / 2).roundToDouble();

  return _SceneMetrics(
    isNarrow: isNarrow,
    gutter: gutter,
    colGap: colGap,
    bottomGap: bottomGap,
    orbScale: orbScale,
    activeOrbCount: activeOrbCount,
    bodyTop: bodyTop,
    bodyHeight: bodyHeight,
    columnCount: columnCount,
    columnWidth: columnWidth,
    contentLeft: contentLeft,
    contentWidth: contentWidth,
    headlineFit: headlineFit,
  );
}

Rect _logoRectForScene(_FloatingLogo logo, _SceneMetrics metrics, Size size) {
  final width = (size.width * (metrics.isNarrow ? 0.34 : 0.25))
      .clamp(metrics.isNarrow ? 140.0 : 220.0, metrics.isNarrow ? 210.0 : 320.0);
  final height = width / kFlutterTextLogoMask.aspectRatio;
  return Rect.fromLTWH(logo.x, logo.y, width, height);
}

_HeadlineFit _fitHeadline(
  double maxWidth,
  double maxHeight,
  double maxSize,
) {
  var lo = 18.0;
  var hi = maxSize;
  var bestSize = lo;
  var bestLines = <_PositionedLine>[];

  while (lo <= hi) {
    final size = ((lo + hi) / 2).floorToDouble();
    final style = TextStyle(
      fontFamily: 'Georgia',
      fontWeight: FontWeight.w900,
      fontSize: size,
      letterSpacing: 2,
      height: 1.0,
    );
    final lineH = (size * 0.93).roundToDouble();
    final prepared = prepareWithSegments(_kHeadlineText, style);
    var breaksWord = false;
    var lineCount = 0;

    walkLineRanges(prepared, maxWidth, (line) {
      lineCount++;
      if (line.end.graphemeIndex != 0) breaksWord = true;
    });

    final totalH = lineCount * lineH;
    if (!breaksWord && totalH <= maxHeight) {
      bestSize = size;
      final result = layoutWithLines(prepared, maxWidth, lineH);
      bestLines = result.lines
          .asMap()
          .entries
          .map((e) => _PositionedLine(
                x: 0,
                y: e.key * lineH,
                width: e.value.width,
                text: e.value.text,
              ))
          .toList();
      lo = size + 1;
    } else {
      hi = size - 1;
    }
  }

  return _HeadlineFit(bestSize, bestLines);
}

// ---------------------------------------------------------------------------
// Column layout engine
// ---------------------------------------------------------------------------

class _ColumnResult {
  const _ColumnResult(this.lines, this.cursor);
  final List<_PositionedLine> lines;
  final LayoutCursor cursor;
}

_ColumnResult _layoutColumn({
  required PreparedTextWithSegments prepared,
  required LayoutCursor startCursor,
  required double regionX,
  required double regionY,
  required double regionW,
  required double regionH,
  required double lineHeight,
  required List<_Orb> circleObstacles,
  required double orbScale,
  required List<_RectObstacle> rectObstacles,
  required List<FlutterTextLogoObstacle> logoObstacles,
  required bool singleSlotOnly,
}) {
  var cursor = startCursor;
  var lineTop = regionY;
  final lines = <_PositionedLine>[];
  var textExhausted = false;

  while (lineTop + lineHeight <= regionY + regionH && !textExhausted) {
    final bandTop = lineTop;
    final bandBottom = lineTop + lineHeight;
    final blocked = <_Interval>[];

    for (final orb in circleObstacles) {
      final scaledR = orb.r * orbScale;
      final interval = _circleIntervalForBand(
        orb.x,
        orb.y,
        scaledR,
        bandTop,
        bandBottom,
      );
      if (interval != null) blocked.add(interval);
    }

    for (final rect in rectObstacles) {
      if (bandBottom <= rect.y || bandTop >= rect.y + rect.h) continue;
      blocked.add(_Interval(rect.x, rect.x + rect.w));
    }

    for (final logo in logoObstacles) {
      for (final interval in logo.intervalsForBand(bandTop, bandBottom)) {
        blocked.add(_Interval(
          interval.$1 - _kLogoPadding,
          interval.$2 + _kLogoPadding,
        ));
      }
    }

    final slots = _carveLineSlots(
      _Interval(regionX, regionX + regionW),
      blocked,
    );
    if (slots.isEmpty) {
      lineTop += lineHeight;
      continue;
    }

    final orderedSlots = singleSlotOnly
        ? [
            slots.reduce((best, slot) {
              final bestW = best.right - best.left;
              final slotW = slot.right - slot.left;
              if (slotW > bestW) return slot;
              if (slotW < bestW) return best;
              return slot.left < best.left ? slot : best;
            })
          ]
        : (List<_Interval>.of(slots)..sort((a, b) => a.left.compareTo(b.left)));

    for (final slot in orderedSlots) {
      final slotWidth = slot.right - slot.left;
      final line = layoutNextLine(prepared, cursor, slotWidth);
      if (line == null) {
        textExhausted = true;
        break;
      }
      lines.add(_PositionedLine(
        x: slot.left,
        y: lineTop,
        text: line.text,
        width: line.width,
      ));
      cursor = line.end;
    }

    lineTop += lineHeight;
  }

  return _ColumnResult(lines, cursor);
}

// ---------------------------------------------------------------------------
// Hit test helper
// ---------------------------------------------------------------------------

int _hitTestOrbs(
  List<_Orb> orbs,
  double px,
  double py,
  int activeCount,
  double radiusScale,
) {
  for (var i = activeCount - 1; i >= 0; i--) {
    final orb = orbs[i];
    final radius = orb.r * radiusScale;
    final dx = px - orb.x;
    final dy = py - orb.y;
    if (dx * dx + dy * dy <= radius * radius) return i;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Editorial Engine Demo Page
// ---------------------------------------------------------------------------

class EditorialEngineDemoPage extends StatefulWidget {
  const EditorialEngineDemoPage({super.key});

  @override
  State<EditorialEngineDemoPage> createState() =>
      _EditorialEngineDemoPageState();
}

class _EditorialEngineDemoPageState extends State<EditorialEngineDemoPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  // Prepared text (measured once)
  PreparedTextWithSegments? _preparedBody;
  PreparedTextWithSegments? _preparedPullquote;
  PreparedTextWithSegments? _preparedLogo;
  double _dropCapWidth = 0;

  // Orbs
  late final List<_Orb> _orbs;
  bool _orbsInitialized = false;

  // Floating Flutter text logo
  final _logo = _FloatingLogo(x: 0, y: 0, vx: -18, vy: 14);
  bool _logoInitialized = false;

  // Drag state
  int _dragOrbIndex = -1;
  Offset _dragStartPointer = Offset.zero;
  Offset _dragStartOrb = Offset.zero;

  // Text styles
  static const _bodyStyle = TextStyle(
    fontFamily: 'Georgia',
    fontSize: _kBodyFontSize,
    color: _kTextColor,
    height: 1.0,
  );

  static const _pullquoteStyle = TextStyle(
    fontFamily: 'Georgia',
    fontStyle: FontStyle.italic,
    fontSize: 17,
    color: _kTextColor,
    height: 1.0,
  );

  static const _logoStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: _kLogoFontSize,
    color: kFlutterLogoLightBlue,
    height: _kLogoLineHeight / _kLogoFontSize,
  );

  @override
  void initState() {
    super.initState();
    _orbs = _kOrbDefs
        .map((d) => _Orb(
              x: 0,
              y: 0,
              r: d.r,
              vx: d.vx,
              vy: d.vy,
              color: d.color,
            ))
        .toList();

    _ticker = createTicker(_onTick)..start();

    // Defer preparation until after first frame so binding is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareText();
    });
  }

  void _prepareText() {
    _preparedBody = prepareWithSegments(_kBodyText, _bodyStyle);
    _preparedPullquote = prepareWithSegments(_kPullquoteText, _pullquoteStyle);
    _preparedLogo = prepareWithSegments(
      '$kFlutterLogoText $kFlutterLogoText $kFlutterLogoText $kFlutterLogoText',
      _logoStyle,
    );

    // Measure drop cap width
    final dropCapSize = _kBodyLineHeight * _kDropCapLines - 4;
    final dropCapStyle = TextStyle(
      fontFamily: 'Georgia',
      fontWeight: FontWeight.w700,
      fontSize: dropCapSize,
      color: _kTextColor,
      height: 1.0,
    );
    final dropCapPrepared =
        prepareWithSegments(_kBodyText[0], dropCapStyle);
    final dropCapResult = layoutWithLines(dropCapPrepared, 9999, dropCapSize);
    if (dropCapResult.lines.isNotEmpty) {
      _dropCapWidth = dropCapResult.lines.first.width.ceilToDouble() + 10;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_preparedBody == null || _preparedLogo == null) return;
    final dt =
        min((elapsed - _lastElapsed).inMicroseconds / 1000000.0, _kMaxDt);
    _lastElapsed = elapsed;

    final size = MediaQuery.of(context).size;
    final metrics = _computeSceneMetrics(size);
    final orbScale = metrics.orbScale;
    final activeCount = metrics.activeOrbCount;
    final gutter = metrics.gutter;
    final bottomGap = metrics.bottomGap;

    // Initialize orb positions once we know the size
    if (!_orbsInitialized) {
      for (var i = 0; i < _orbs.length; i++) {
        _orbs[i].x = _kOrbDefs[i].fx * size.width;
        _orbs[i].y = _kOrbDefs[i].fy * size.height;
      }
      _orbsInitialized = true;
    }

    if (!_logoInitialized) {
      final initialRect = _logoRectForScene(_logo, metrics, size);
      _logo.x = metrics.contentLeft + metrics.contentWidth - initialRect.width;
      _logo.y = metrics.bodyTop + metrics.bodyHeight * 0.12;
      _logoInitialized = true;
    }

    var anyMoving = false;

    for (var i = 0; i < activeCount; i++) {
      final orb = _orbs[i];
      final radius = orb.r * orbScale;
      if (orb.paused || i == _dragOrbIndex) continue;
      anyMoving = true;

      orb.x += orb.vx * dt;
      orb.y += orb.vy * dt;

      if (orb.x - radius < 0) {
        orb.x = radius;
        orb.vx = orb.vx.abs();
      }
      if (orb.x + radius > size.width) {
        orb.x = size.width - radius;
        orb.vx = -orb.vx.abs();
      }
      if (orb.y - radius < gutter * 0.5) {
        orb.y = radius + gutter * 0.5;
        orb.vy = orb.vy.abs();
      }
      if (orb.y + radius > size.height - bottomGap) {
        orb.y = size.height - bottomGap - radius;
        orb.vy = -orb.vy.abs();
      }
    }

    final logoRect = _logoRectForScene(_logo, metrics, size);
    if (!_logo.paused) {
      anyMoving = true;
      _logo.x += _logo.vx * dt;
      _logo.y += _logo.vy * dt;

      final minX = metrics.contentLeft;
      final maxX = metrics.contentLeft + metrics.contentWidth - logoRect.width;
      final minY = metrics.bodyTop + _kLogoBodyGap;
      final maxY =
          size.height - bottomGap - logoRect.height - _kLogoBodyGap;

      if (_logo.x < minX) {
        _logo.x = minX;
        _logo.vx = _logo.vx.abs();
      }
      if (_logo.x > maxX) {
        _logo.x = maxX;
        _logo.vx = -_logo.vx.abs();
      }
      if (_logo.y < minY) {
        _logo.y = minY;
        _logo.vy = _logo.vy.abs();
      }
      if (_logo.y > maxY) {
        _logo.y = maxY;
        _logo.vy = -_logo.vy.abs();
      }
    }

    // Orb-orb separation
    for (var i = 0; i < activeCount; i++) {
      final a = _orbs[i];
      final aR = a.r * orbScale;
      for (var j = i + 1; j < activeCount; j++) {
        final b = _orbs[j];
        final bR = b.r * orbScale;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final dist = sqrt(dx * dx + dy * dy);
        final minDist = aR + bR + _kOrbSeparationGap;
        if (dist >= minDist || dist <= 0.1) continue;

        final force = (minDist - dist) * _kSeparationForce;
        final nx = dx / dist;
        final ny = dy / dist;

        if (!a.paused && i != _dragOrbIndex) {
          a.vx -= nx * force * dt;
          a.vy -= ny * force * dt;
        }
        if (!b.paused && j != _dragOrbIndex) {
          b.vx += nx * force * dt;
          b.vy += ny * force * dt;
        }
      }
    }

    final updatedLogoRect = _logoRectForScene(_logo, metrics, size);
    for (var i = 0; i < activeCount; i++) {
      final orb = _orbs[i];
      final radius = orb.r * orbScale;
      final nearestX = max(updatedLogoRect.left, min(orb.x, updatedLogoRect.right));
      final nearestY = max(updatedLogoRect.top, min(orb.y, updatedLogoRect.bottom));
      final dx = orb.x - nearestX;
      final dy = orb.y - nearestY;
      final dist = sqrt(dx * dx + dy * dy);
      final minDist = radius + 10;
      if (dist >= minDist || dist == 0) continue;

      final nx = dx / dist;
      final ny = dy / dist;
      final push = (minDist - dist) * 0.8;
      _logo.x -= nx * push;
      _logo.y -= ny * push;
      _logo.vx -= nx * 12 * dt;
      _logo.vy -= ny * 12 * dt;
    }

    // Always mark dirty so the painter repaints
    if (anyMoving || _dragOrbIndex != -1) {
      setState(() {});
    }
  }

  void _onPanStart(DragStartDetails details) {
    final pos = details.localPosition;
    final isNarrow =
        MediaQuery.of(context).size.width < _kNarrowBreakpoint;
    final orbScale = isNarrow ? _kNarrowOrbScale : 1.0;
    final activeCount =
        isNarrow ? min(_kNarrowActiveOrbs, _orbs.length) : _orbs.length;

    final hit =
        _hitTestOrbs(_orbs, pos.dx, pos.dy, activeCount, orbScale);
    if (hit != -1) {
      _dragOrbIndex = hit;
      _dragStartPointer = pos;
      _dragStartOrb = Offset(_orbs[hit].x, _orbs[hit].y);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragOrbIndex == -1) return;
    final pos = details.localPosition;
    _orbs[_dragOrbIndex].x =
        _dragStartOrb.dx + (pos.dx - _dragStartPointer.dx);
    _orbs[_dragOrbIndex].y =
        _dragStartOrb.dy + (pos.dy - _dragStartPointer.dy);
    setState(() {});
  }

  void _onPanEnd(DragEndDetails details) {
    if (_dragOrbIndex == -1) return;
    // Toggle pause on tap (small drag distance)
    final orb = _orbs[_dragOrbIndex];
    final dx = orb.x - _dragStartOrb.dx;
    final dy = orb.y - _dragStartOrb.dy;
    if (dx * dx + dy * dy < _kDragTapThreshold) {
      orb.paused = !orb.paused;
    }
    _dragOrbIndex = -1;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: SizedBox.expand(
          child: _preparedBody == null
              ? const SizedBox.shrink()
              : CustomPaint(
                  painter: _EditorialPainter(
                    preparedBody: _preparedBody!,
                    preparedPullquote: _preparedPullquote!,
                    preparedLogo: _preparedLogo!,
                    orbs: _orbs,
                    logo: _logo,
                    dropCapWidth: _dropCapWidth,
                    bodyStyle: _bodyStyle,
                    pullquoteStyle: _pullquoteStyle,
                    logoStyle: _logoStyle,
                  ),
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom Painter
// ---------------------------------------------------------------------------

class _EditorialPainter extends CustomPainter {
  _EditorialPainter({
    required this.preparedBody,
    required this.preparedPullquote,
    required this.preparedLogo,
    required this.orbs,
    required this.logo,
    required this.dropCapWidth,
    required this.bodyStyle,
    required this.pullquoteStyle,
    required this.logoStyle,
  });

  final PreparedTextWithSegments preparedBody;
  final PreparedTextWithSegments preparedPullquote;
  final PreparedTextWithSegments preparedLogo;
  final List<_Orb> orbs;
  final _FloatingLogo logo;
  final double dropCapWidth;
  final TextStyle bodyStyle;
  final TextStyle pullquoteStyle;
  final TextStyle logoStyle;

  @override
  bool shouldRepaint(covariant _EditorialPainter oldDelegate) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _computeSceneMetrics(size);
    final isNarrow = metrics.isNarrow;
    final gutter = metrics.gutter;
    final colGap = metrics.colGap;
    final bottomGap = metrics.bottomGap;
    final orbScale = metrics.orbScale;
    final activeOrbCount = metrics.activeOrbCount;
    final headlineFit = metrics.headlineFit;

    // Paint headline
    for (var i = 0; i < headlineFit.lines.length; i++) {
      final line = headlineFit.lines[i];
      _paintTextLine(
        canvas,
        line.text,
        Offset(gutter + line.x, gutter + line.y),
        TextStyle(
          fontFamily: 'Georgia',
          fontWeight: FontWeight.w900,
          fontSize: headlineFit.fontSize,
          color: _kTextColor,
          letterSpacing: 2,
          height: 1.0,
        ),
      );
    }

    // --- Body layout ---
    final bodyTop = metrics.bodyTop;
    final bodyHeight = metrics.bodyHeight;
    final columnCount = metrics.columnCount;
    final columnWidth = metrics.columnWidth;
    final contentLeft = metrics.contentLeft;

    // Drop cap rect obstacle
    final dropCapRect = _RectObstacle(
      contentLeft - 2,
      bodyTop - 2,
      dropCapWidth,
      _kDropCapLines * _kBodyLineHeight + 2,
    );

    // Pull quote placement (skip on narrow)
    _RectObstacle? pullquoteRect;
    List<_PositionedLine> pullquoteLines = [];
    int pullquoteColIdx = -1;

    if (!isNarrow && columnCount >= 2) {
      pullquoteColIdx = 1;
      final pqWidth = (columnWidth * 0.5).roundToDouble();
      final pqLayoutResult =
          layoutWithLines(preparedPullquote, pqWidth - 20, 25);
      final pqHeight = pqLayoutResult.lines.length * 25.0 + 16;
      final col1X = contentLeft + 1 * (columnWidth + colGap);
      final pqX = col1X; // left side of second column
      final pqY = (bodyTop + bodyHeight * 0.32).roundToDouble();

      pullquoteRect = _RectObstacle(pqX, pqY, pqWidth, pqHeight);
      pullquoteLines = pqLayoutResult.lines
          .asMap()
          .entries
          .map((e) => _PositionedLine(
                x: pqX + 20,
                y: pqY + 8 + e.key * 25.0,
                width: e.value.width,
                text: e.value.text,
              ))
          .toList();
    }

    // Active circle obstacles
    final activeOrbs = orbs.sublist(0, activeOrbCount);
    final logoRect = _logoRectForScene(logo, metrics, size);
    final logoObstacle = FlutterTextLogoObstacle(
      mask: kFlutterTextLogoMask,
      rect: logoRect,
      lineHeight: _kLogoLineHeight,
    );

    // --- Layout columns ---
    final allBodyLines = <_PositionedLine>[];
    // Start body after the first character (drop cap)
    var cursor =
        const LayoutCursor(segmentIndex: 0, graphemeIndex: 1);

    for (var col = 0; col < columnCount; col++) {
      final colX = contentLeft + col * (columnWidth + colGap);
      final rects = <_RectObstacle>[];
      if (col == 0) rects.add(dropCapRect);
      if (pullquoteRect != null && pullquoteColIdx == col) {
        rects.add(pullquoteRect);
      }

      final result = _layoutColumn(
        prepared: preparedBody,
        startCursor: cursor,
        regionX: colX,
        regionY: bodyTop,
        regionW: columnWidth,
        regionH: bodyHeight,
        lineHeight: _kBodyLineHeight,
        circleObstacles: activeOrbs,
        orbScale: orbScale,
        rectObstacles: rects,
        logoObstacles: [logoObstacle],
        singleSlotOnly: isNarrow,
      );
      allBodyLines.addAll(result.lines);
      cursor = result.cursor;
    }

    // --- Paint column dividers ---
    final dividerPaint = Paint()..color = _kDividerColor;
    for (var col = 1; col < columnCount; col++) {
      final divX =
          contentLeft + col * (columnWidth + colGap) - colGap / 2;
      canvas.drawLine(
        Offset(divX, bodyTop),
        Offset(divX, bodyTop + bodyHeight),
        dividerPaint,
      );
    }

    // --- Paint pull quote box ---
    if (pullquoteRect != null) {
      final pqBoxPaint = Paint()
        ..color = const Color(0x0AFFFFFF)
        ..style = PaintingStyle.fill;
      final pqBorderPaint = Paint()
        ..color = _kPullquoteBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          pullquoteRect.x,
          pullquoteRect.y,
          pullquoteRect.w,
          pullquoteRect.h,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(rrect, pqBoxPaint);
      canvas.drawRRect(rrect, pqBorderPaint);

      // Paint pull quote text
      for (final line in pullquoteLines) {
        _paintTextLine(
          canvas,
          line.text,
          Offset(line.x, line.y),
          pullquoteStyle.copyWith(
            color: _kTextColor.withValues(alpha: 0.85),
          ),
        );
      }
    }

    // --- Paint drop cap ---
    final dropCapSize = _kBodyLineHeight * _kDropCapLines - 4;
    _paintTextLine(
      canvas,
      _kBodyText[0],
      Offset(contentLeft, bodyTop),
      TextStyle(
        fontFamily: 'Georgia',
        fontWeight: FontWeight.w700,
        fontSize: dropCapSize,
        color: _kTextColor,
        height: 1.0,
      ),
    );

    // --- Paint body text ---
    for (final line in allBodyLines) {
      _paintTextLine(
        canvas,
        line.text,
        Offset(line.x, line.y),
        bodyStyle,
      );
    }

    // --- Paint orbs ---
    for (var i = 0; i < activeOrbCount; i++) {
      _paintOrb(canvas, orbs[i], orbScale);
    }

    // --- Floating Flutter text logo ---
    final logoLines = logoObstacle.layoutText(preparedLogo);
    final logoGlowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28)
      ..color = kFlutterLogoLightBlue.withValues(alpha: 0.09);
    canvas.drawRRect(
      RRect.fromRectAndRadius(logoRect.inflate(10), const Radius.circular(18)),
      logoGlowPaint,
    );
    for (final line in logoLines) {
      _paintTextLine(
        canvas,
        line.text,
        Offset(line.x, line.y),
        logoStyle.copyWith(color: line.color),
      );
    }

    // "pretext_flutter" badge (top-right)
    _paintTextLine(
      canvas,
      'pretext_flutter',
      Offset(size.width - gutter - (isNarrow ? 95 : 110), gutter - 2),
      TextStyle(
        fontFamily: 'monospace',
        fontSize: isNarrow ? 10 : 12,
        color: const Color(0x66FFFFFF),
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );

    // Author credit (bottom-left)
    _paintTextLine(
      canvas,
      'by Nathan Kim  \u00B7  github.com/nathankim0',
      Offset(gutter, size.height - bottomGap - 14),
      TextStyle(
        fontFamily: 'Helvetica Neue',
        fontSize: isNarrow ? 10 : 12,
        color: const Color(0x55FFFFFF),
        letterSpacing: 0.3,
      ),
    );
  }

  // ---- Painting helpers ----

  void _paintTextLine(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, offset);
    tp.dispose();
  }

  void _paintOrb(Canvas canvas, _Orb orb, double scale) {
    final r = orb.r * scale;
    final center = Offset(orb.x, orb.y);
    final opacity = orb.paused ? 0.45 : 1.0;

    // Outer glow
    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40)
      ..shader = ui.Gradient.radial(
        center,
        r * 1.3,
        [
          orb.color.withValues(alpha: 0.18 * opacity),
          orb.color.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(center, r * 1.3, glowPaint);

    // Inner gradient sphere
    final highlight = Offset(orb.x - r * 0.2, orb.y - r * 0.2);
    final spherePaint = Paint()
      ..shader = ui.Gradient.radial(
        highlight,
        r * 1.1,
        [
          orb.color.withValues(alpha: 0.38 * opacity),
          orb.color.withValues(alpha: 0.14 * opacity),
          Colors.transparent,
        ],
        [0.0, 0.55, 0.85],
      );
    canvas.drawCircle(center, r, spherePaint);

    // Glass highlight
    final glassPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(orb.x - r * 0.3, orb.y - r * 0.35),
        r * 0.6,
        [
          Colors.white.withValues(alpha: 0.22 * opacity),
          Colors.white.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(
      Offset(orb.x - r * 0.1, orb.y - r * 0.15),
      r * 0.55,
      glassPaint,
    );
  }
}

class _HeadlineFit {
  const _HeadlineFit(this.fontSize, this.lines);
  final double fontSize;
  final List<_PositionedLine> lines;
}
