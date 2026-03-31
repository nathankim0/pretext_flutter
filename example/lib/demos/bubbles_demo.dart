import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pretext_flutter/pretext_flutter.dart';

// ---------------------------------------------------------------------------
// Layout constants (mirrors bubbles-shared.ts)
// ---------------------------------------------------------------------------

const _kFontSize = 15.0;
const _kLineHeight = 20.0;
const _kPaddingH = 12.0;
const _kPaddingV = 8.0;
const _kBubbleMaxRatio = 0.8;
const _kBubbleRadius = 18.0;

const _kSliderMin = 200.0;
const _kSliderMax = 400.0;
const _kSliderDefault = 320.0;

const _kColumnGap = 16.0;

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

const _kBlueBubble = Color(0xFF007AFF);
const _kGrayBubble = Color(0xFFE9E9EB);
const _kBlueBubbleText = Colors.white;
const _kGrayBubbleText = Color(0xFF1C1C1E);
const _kWastedAreaColor = Color(0x30FF3B30);
const _kSavedColor = Color(0xFF34C759);
const _kWastedColor = Color(0xFFFF3B30);
const _kPageBackground = Color(0xFFF2F2F7);
const _kPanelBackground = Colors.white;

// ---------------------------------------------------------------------------
// Chat messages
// ---------------------------------------------------------------------------

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isMe});
  final String text;
  final bool isMe;
}

const _kMessages = [
  _ChatMessage(text: 'Hey! How are you doing? \u{1F60A}', isMe: false),
  _ChatMessage(
      text: 'Pretty good! Just shipped a new feature.', isMe: true),
  _ChatMessage(text: '\uC624 \uB300\uBC15 \uBB50 \uB9CC\uB4E0\uAC70\uC57C?', isMe: false),
  _ChatMessage(
    text:
        'A text layout engine that works without DOM measurements. '
        'It caches segment widths and does pure arithmetic for layout. '
        '60fps reflow around obstacles!',
    isMe: true,
  ),
  _ChatMessage(
      text: 'Wait, that actually sounds really cool \u{1F525}', isMe: false),
  _ChatMessage(
    text:
        'Yeah, check out the demo \u2014 you can drag circles around '
        'and text reflows in real-time',
    isMe: true,
  ),
  _ChatMessage(
    text:
        '\u3053\u308C\u306F\u3059\u3054\u3044\uFF01'
        'Flutter\u3067\u3082CSS\u3067\u3082\u306A\u3044\u3001'
        '\u7D14\u7C8B\u306A\u6570\u5B66\u3060\u3051\u3067'
        '\u30C6\u30AD\u30B9\u30C8\u30EC\u30A4\u30A2\u30A6\u30C8\u304C'
        '\u3067\u304D\u308B\u306E\uFF1F',
    isMe: false,
  ),
  _ChatMessage(
    text:
        "Exactly. And look at how tight these bubbles are \u2014 "
        "no wasted space. That's shrinkwrap layout.",
    isMe: true,
  ),
  _ChatMessage(text: '\u{1F44F}\u{1F44F}\u{1F44F}', isMe: false),
];

// ---------------------------------------------------------------------------
// Prepared bubble data
// ---------------------------------------------------------------------------

class _PreparedBubble {
  _PreparedBubble({required this.prepared, required this.message});
  final PreparedTextWithSegments prepared;
  final _ChatMessage message;
}

class _BubbleWidths {
  const _BubbleWidths({
    required this.cssWidth,
    required this.tightWidth,
  });
  final double cssWidth;
  final double tightWidth;
}

// ---------------------------------------------------------------------------
// Shrinkwrap math (port of bubbles-shared.ts)
// ---------------------------------------------------------------------------

class _WrapMetrics {
  const _WrapMetrics({
    required this.lineCount,
    required this.height,
    required this.maxLineWidth,
  });
  final int lineCount;
  final double height;
  final double maxLineWidth;
}

_WrapMetrics _collectWrapMetrics(
  PreparedTextWithSegments prepared,
  double maxWidth,
) {
  double maxLineWidth = 0;
  final lineCount = walkLineRanges(prepared, maxWidth, (line) {
    if (line.width > maxLineWidth) maxLineWidth = line.width;
  });
  return _WrapMetrics(
    lineCount: lineCount,
    height: lineCount * _kLineHeight,
    maxLineWidth: maxLineWidth,
  );
}

_WrapMetrics _findTightWrapMetrics(
  PreparedTextWithSegments prepared,
  double maxWidth,
) {
  final initial = _collectWrapMetrics(prepared, maxWidth);
  int lo = 1;
  int hi = math.max(1, maxWidth.ceil());

  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    final midResult = layout(prepared, mid.toDouble(), _kLineHeight);
    if (midResult.lineCount <= initial.lineCount) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }

  return _collectWrapMetrics(prepared, lo.toDouble());
}

List<_BubbleWidths> _computeBubbleWidths(
  List<_PreparedBubble> bubbles,
  double chatWidth,
) {
  final bubbleMaxWidth = (chatWidth * _kBubbleMaxRatio).floorToDouble();
  final contentMaxWidth = bubbleMaxWidth - _kPaddingH * 2;
  final result = <_BubbleWidths>[];

  for (final bubble in bubbles) {
    final cssMetrics = _collectWrapMetrics(bubble.prepared, contentMaxWidth);
    final tightMetrics =
        _findTightWrapMetrics(bubble.prepared, contentMaxWidth);

    final cssWidth =
        cssMetrics.maxLineWidth.ceilToDouble() + _kPaddingH * 2;
    final tightWidth =
        tightMetrics.maxLineWidth.ceilToDouble() + _kPaddingH * 2;
    result.add(_BubbleWidths(cssWidth: cssWidth, tightWidth: tightWidth));
  }

  return result;
}

int _computeTotalWaste(List<_BubbleWidths> widths) {
  int total = 0;
  for (final w in widths) {
    total += math.max(0, (w.cssWidth - w.tightWidth).round());
  }
  return total;
}

// ---------------------------------------------------------------------------
// Widget: BubblesDemo
// ---------------------------------------------------------------------------

class BubblesDemo extends StatefulWidget {
  const BubblesDemo({super.key});

  @override
  State<BubblesDemo> createState() => _BubblesDemoState();
}

class _BubblesDemoState extends State<BubblesDemo>
    with TickerProviderStateMixin {
  static const _kTextStyle = TextStyle(
    fontSize: _kFontSize,
    fontFamily: '.SF Pro Text',
    height: _kLineHeight / _kFontSize,
    color: Colors.black,
  );

  double _chatWidth = _kSliderDefault;
  List<_PreparedBubble>? _prepared;

  // Animated counter
  late AnimationController _counterController;
  int _displayedCssWaste = 0;
  int _targetCssWaste = 0;
  int _displayedShrinkWaste = 0;
  int _targetShrinkWaste = 0;

  @override
  void initState() {
    super.initState();
    _counterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(_onCounterTick);
    _initPrepared();
  }

  void _initPrepared() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prepared = _kMessages.map((msg) {
        return _PreparedBubble(
          prepared: prepareWithSegments(msg.text, _kTextStyle),
          message: msg,
        );
      }).toList();
      setState(() {
        _prepared = prepared;
      });
      _recompute();
    });
  }

  @override
  void dispose() {
    _counterController.dispose();
    super.dispose();
  }

  void _onCounterTick() {
    final t = _counterController.value;
    setState(() {
      _displayedCssWaste =
          (_previousCssWaste + (_targetCssWaste - _previousCssWaste) * t)
              .round();
      _displayedShrinkWaste =
          (_previousShrinkWaste +
                  (_targetShrinkWaste - _previousShrinkWaste) * t)
              .round();
    });
  }

  int _previousCssWaste = 0;
  int _previousShrinkWaste = 0;

  void _recompute() {
    if (_prepared == null) return;
    final widths = _computeBubbleWidths(_prepared!, _chatWidth);
    final cssWaste = _computeTotalWaste(widths);

    _previousCssWaste = _displayedCssWaste;
    _previousShrinkWaste = _displayedShrinkWaste;
    _targetCssWaste = cssWaste;
    _targetShrinkWaste = 0;

    _counterController
      ..reset()
      ..forward();
  }

  void _onSliderChanged(double value) {
    setState(() {
      _chatWidth = value.roundToDouble();
    });
    _recompute();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBackground,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlutterLogo(size: 24),
            SizedBox(width: 8),
            Text('Shrinkwrap Bubbles'),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'by Nathan Kim',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8E8E93),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSliderHeader(),
          Expanded(
            child: _prepared == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _buildComparison(),
          ),
          // Footer branding
          Container(
            color: _kPanelBackground,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FlutterLogo(size: 18),
                  SizedBox(width: 6),
                  Text(
                    'pretext_flutter  \u00B7  Powered by Flutter',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8E8E93),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderHeader() {
    return Container(
      color: _kPanelBackground,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Column(
        children: [
          // Width label
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Chat Width  ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8E8E93),
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_chatWidth.round()}px',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Slider
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _kBlueBubble,
              inactiveTrackColor: const Color(0xFFD1D1D6),
              thumbColor: Colors.white,
              overlayColor: _kBlueBubble.withAlpha(30),
              trackHeight: 4,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 14),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 22),
            ),
            child: Slider(
              min: _kSliderMin,
              max: _kSliderMax,
              value: _chatWidth,
              onChanged: _onSliderChanged,
            ),
          ),
          const SizedBox(height: 12),
          // Waste counters
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildWasteLabel(
                title: 'CSS Waste',
                pixels: _displayedCssWaste,
                color: _kWastedColor,
              ),
              _buildWasteLabel(
                title: 'Shrinkwrap Waste',
                pixels: _displayedShrinkWaste,
                color: _kSavedColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWasteLabel({
    required String title,
    required int pixels,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFF8E8E93),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${_formatNumber(pixels)} px',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildComparison() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildColumn(
                  title: 'Normal (CSS)',
                  useShrinkwrap: false,
                ),
              ),
              const SizedBox(width: _kColumnGap),
              Expanded(
                child: _buildColumn(
                  title: 'Shrinkwrap',
                  useShrinkwrap: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildColumn({
    required String title,
    required bool useShrinkwrap,
  }) {
    final bubbleMaxWidth = (_chatWidth * _kBubbleMaxRatio).floorToDouble();

    List<_BubbleWidths>? widths;
    if (_prepared != null) {
      widths = _computeBubbleWidths(_prepared!, _chatWidth);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Column title
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: useShrinkwrap ? _kSavedColor : _kWastedColor,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Chat container
        Center(
          child: SizedBox(
            width: _chatWidth,
            child: Container(
              decoration: BoxDecoration(
                color: _kPanelBackground,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_prepared != null && widths != null)
                    for (int i = 0; i < _prepared!.length; i++)
                      _buildBubble(
                        bubble: _prepared![i],
                        widths: widths[i],
                        bubbleMaxWidth: bubbleMaxWidth,
                        useShrinkwrap: useShrinkwrap,
                        isLast: i == _prepared!.length - 1,
                      ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBubble({
    required _PreparedBubble bubble,
    required _BubbleWidths widths,
    required double bubbleMaxWidth,
    required bool useShrinkwrap,
    required bool isLast,
  }) {
    final isMe = bubble.message.isMe;
    final displayWidth =
        useShrinkwrap ? widths.tightWidth : widths.cssWidth;
    final wastedWidth = widths.cssWidth - widths.tightWidth;
    final showWasteOverlay = !useShrinkwrap && wastedWidth > 1;

    final bubbleColor = isMe ? _kBlueBubble : _kGrayBubble;
    final textColor = isMe ? _kBlueBubbleText : _kGrayBubbleText;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Stack(
          children: [
            // Main bubble
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              constraints: BoxConstraints(
                maxWidth: math.min(displayWidth, bubbleMaxWidth),
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(_kBubbleRadius),
                  topRight: const Radius.circular(_kBubbleRadius),
                  bottomLeft: Radius.circular(isMe ? _kBubbleRadius : 4),
                  bottomRight: Radius.circular(isMe ? 4 : _kBubbleRadius),
                ),
                boxShadow: [
                  BoxShadow(
                    color: bubbleColor.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: _kPaddingH,
                vertical: _kPaddingV,
              ),
              child: Text(
                bubble.message.text,
                style: _kTextStyle.copyWith(color: textColor),
              ),
            ),
            // Wasted area overlay (only for normal/CSS mode)
            if (showWasteOverlay)
              Positioned(
                right: isMe ? 0 : null,
                left: isMe ? null : null,
                top: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: math.max(0, wastedWidth),
                  decoration: BoxDecoration(
                    color: _kWastedAreaColor,
                    borderRadius: BorderRadius.only(
                      topRight: isMe
                          ? Radius.zero
                          : const Radius.circular(_kBubbleRadius),
                      bottomRight: isMe
                          ? Radius.zero
                          : const Radius.circular(_kBubbleRadius),
                      topLeft: isMe
                          ? const Radius.circular(_kBubbleRadius)
                          : Radius.zero,
                      bottomLeft: isMe
                          ? const Radius.circular(_kBubbleRadius)
                          : Radius.zero,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _formatNumber(int value) {
  if (value < 1000) return '$value';
  final thousands = value ~/ 1000;
  final remainder = value % 1000;
  return '$thousands,${remainder.toString().padLeft(3, '0')}';
}
