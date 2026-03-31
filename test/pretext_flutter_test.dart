import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:pretext_flutter/pretext_flutter.dart';
import 'package:pretext_flutter/src/analysis.dart';
import 'package:pretext_flutter/src/line_break.dart' show countPreparedLines, walkPreparedLines;
import 'package:pretext_flutter/src/measurement.dart';
import 'package:pretext_flutter/src/types.dart' show SegmentBreakKind;

// ---------------------------------------------------------------------------
// Deterministic fake measurer (matches original test's measureWidth logic)
// ---------------------------------------------------------------------------

final _emojiPresentationRe = RegExp(r'\p{Emoji_Presentation}', unicode: true);
final _punctuationRe = RegExp(r'[.,!?;:%)\]}'+"'\"\\u201D\\u2019\\u00BB\\u203A\\u2026\\u2014-]");

bool _isWideCharacter(int code) {
  return (code >= 0x4E00 && code <= 0x9FFF) ||
      (code >= 0x3400 && code <= 0x4DBF) ||
      (code >= 0xF900 && code <= 0xFAFF) ||
      (code >= 0x2F800 && code <= 0x2FA1F) ||
      (code >= 0x20000 && code <= 0x2A6DF) ||
      (code >= 0x2A700 && code <= 0x2B73F) ||
      (code >= 0x2B740 && code <= 0x2B81F) ||
      (code >= 0x2B820 && code <= 0x2CEAF) ||
      (code >= 0x2CEB0 && code <= 0x2EBEF) ||
      (code >= 0x30000 && code <= 0x3134F) ||
      (code >= 0x3000 && code <= 0x303F) ||
      (code >= 0x3040 && code <= 0x309F) ||
      (code >= 0x30A0 && code <= 0x30FF) ||
      (code >= 0xAC00 && code <= 0xD7AF) ||
      (code >= 0xFF00 && code <= 0xFFEF);
}

double _measureWidth(String text, double fontSize) {
  double width = 0;
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (rune == 0x20) {
      width += fontSize * 0.33;
    } else if (rune == 0x09) {
      width += fontSize * 1.32;
    } else if (_emojiPresentationRe.hasMatch(ch) || rune == 0xFE0F) {
      width += fontSize;
    } else if (_isWideCharacter(rune)) {
      width += fontSize;
    } else if (_punctuationRe.hasMatch(ch)) {
      width += fontSize * 0.4;
    } else {
      width += fontSize * 0.6;
    }
  }
  return width;
}

double _nextTabAdvance(double lineWidth, double spaceWidth, [int tabSize = 8]) {
  final tabStopAdvance = spaceWidth * tabSize;
  final remainder = lineWidth % tabStopAdvance;
  if (remainder.abs() < 1e-6) return tabStopAdvance;
  return tabStopAdvance - remainder;
}

class FakeMeasurer extends SegmentMeasurer {
  final double fontSize;
  FakeMeasurer({this.fontSize = 16});

  @override
  double measureSegment(String segment, TextStyle style) {
    final size = style.fontSize ?? fontSize;
    return _measureWidth(segment, size);
  }
}

// ---------------------------------------------------------------------------
// Constants matching original tests
// ---------------------------------------------------------------------------

const _fontSize = 16.0;
const _lineHeight = 19.0;
const _style = TextStyle(fontSize: _fontSize);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakeMeasurer fakeMeasurer;

  setUp(() {
    fakeMeasurer = FakeMeasurer(fontSize: _fontSize);
    testMeasurer = fakeMeasurer;
    clearCache();
  });

  tearDown(() {
    testMeasurer = null;
  });

  group('prepare invariants', () {
    test('whitespace-only input stays empty', () {
      final prepared = prepare('  \t\n  ', _style);
      final result = layout(prepared, 200, _lineHeight);
      expect(result.lineCount, 0);
      expect(result.height, 0);
    });

    test('collapses ordinary whitespace runs and trims the edges', () {
      final prepared = prepareWithSegments('  Hello\t \n  World  ', _style);
      expect(prepared.segments, ['Hello', ' ', 'World']);
    });

    test('pre-wrap mode keeps ordinary spaces instead of collapsing them', () {
      final prepared = prepareWithSegments(
        '  Hello   World  ',
        _style,
        whiteSpace: WhiteSpaceMode.preWrap,
      );
      // Verify all spaces are preserved-space kind and text is text kind
      final spaceCount = prepared.core.kinds
          .where((k) => k == SegmentBreakKind.preservedSpace)
          .length;
      final textCount = prepared.core.kinds
          .where((k) => k == SegmentBreakKind.text)
          .length;
      expect(spaceCount, greaterThan(0));
      expect(textCount, 2); // Hello, World
      // Joining segments should reproduce normalized text
      expect(prepared.segments.join(), '  Hello   World  ');
    });

    test('pre-wrap mode keeps hard breaks as explicit segments', () {
      final prepared = prepareWithSegments(
        'Hello\nWorld',
        _style,
        whiteSpace: WhiteSpaceMode.preWrap,
      );
      expect(prepared.segments, ['Hello', '\n', 'World']);
      expect(prepared.core.kinds, [
        SegmentBreakKind.text,
        SegmentBreakKind.hardBreak,
        SegmentBreakKind.text,
      ]);
    });

    test('pre-wrap mode normalizes CRLF into a single hard break', () {
      final prepared = prepareWithSegments(
        'Hello\r\nWorld',
        _style,
        whiteSpace: WhiteSpaceMode.preWrap,
      );
      expect(prepared.segments, ['Hello', '\n', 'World']);
    });

    test('pre-wrap mode keeps tabs as explicit segments', () {
      final prepared = prepareWithSegments(
        'Hello\tWorld',
        _style,
        whiteSpace: WhiteSpaceMode.preWrap,
      );
      expect(prepared.segments, ['Hello', '\t', 'World']);
      expect(prepared.core.kinds, [
        SegmentBreakKind.text,
        SegmentBreakKind.tab,
        SegmentBreakKind.text,
      ]);
    });

    test('keeps non-breaking spaces as glue instead of collapsing', () {
      final prepared = prepareWithSegments('Hello\u00A0world', _style);
      expect(prepared.segments, ['Hello\u00A0world']);
      expect(prepared.core.kinds, [SegmentBreakKind.text]);
    });

    test('keeps standalone non-breaking spaces as visible glue content', () {
      final prepared = prepareWithSegments('\u00A0', _style);
      expect(prepared.segments, ['\u00A0']);
      final result = layout(prepared, 200, _lineHeight);
      expect(result.lineCount, 1);
      expect(result.height, _lineHeight);
    });

    test('treats zero-width spaces as explicit break opportunities', () {
      final prepared =
          prepareWithSegments('alpha\u200Bbeta', _style);
      expect(prepared.segments, ['alpha', '\u200B', 'beta']);
      expect(prepared.core.kinds, [
        SegmentBreakKind.text,
        SegmentBreakKind.zeroWidthBreak,
        SegmentBreakKind.text,
      ]);

      final alphaWidth = prepared.core.widths[0];
      expect(
        layout(prepared, alphaWidth + 0.1, _lineHeight).lineCount,
        2,
      );
    });

    test('keeps closing punctuation attached to the preceding word', () {
      final prepared = prepareWithSegments('hello.', _style);
      expect(prepared.segments, ['hello.']);
    });

    test('keeps opening quotes attached to the following word', () {
      final prepared = prepareWithSegments('\u201CWhenever', _style);
      expect(prepared.segments, ['\u201CWhenever']);
    });

    test('keeps em dashes breakable', () {
      final prepared = prepareWithSegments('universe\u2014so', _style);
      expect(prepared.segments, ['universe', '\u2014', 'so']);
    });

    test('coalesces repeated punctuation runs into a single segment', () {
      final prepared = prepareWithSegments('=== heading ===', _style);
      expect(prepared.segments, ['===', ' ', 'heading', ' ', '===']);
    });

    test('applies CJK punctuation attachment rules', () {
      final p1 = prepareWithSegments('\u4E2D\u6587\uFF0C\u6D4B\u8BD5\u3002', _style);
      expect(p1.segments, ['\u4E2D', '\u6587\uFF0C', '\u6D4B', '\u8BD5\u3002']);
    });

    test('treats astral CJK ideographs as CJK break units', () {
      final p1 = prepareWithSegments('\u{20000}\u{20001}', _style);
      expect(p1.segments, ['\u{20000}', '\u{20001}']);

      final p2 = prepareWithSegments('\u{20000}\u3002', _style);
      expect(p2.segments, ['\u{20000}\u3002']);
    });

    test('prepare and prepareWithSegments agree on layout', () {
      final plain = prepare('Alpha beta gamma', _style);
      final rich = prepareWithSegments('Alpha beta gamma', _style);
      for (final width in [40.0, 80.0, 200.0]) {
        final plainResult = layout(plain, width, _lineHeight);
        final richResult = layout(rich, width, _lineHeight);
        expect(plainResult.lineCount, richResult.lineCount);
        expect(plainResult.height, richResult.height);
      }
    });
  });

  group('layout invariants', () {
    test('line count grows monotonically as width shrinks', () {
      final prepared =
          prepare('The quick brown fox jumps over the lazy dog', _style);
      int previous = 0;
      for (final width in [320.0, 200.0, 140.0, 90.0]) {
        final result = layout(prepared, width, _lineHeight);
        expect(result.lineCount, greaterThanOrEqualTo(previous));
        previous = result.lineCount;
      }
    });

    test('trailing whitespace hangs past the line edge', () {
      final prepared = prepareWithSegments('Hello ', _style);
      final widthOfHello = prepared.core.widths[0];

      expect(layout(prepared, widthOfHello, _lineHeight).lineCount, 1);

      final withLines = layoutWithLines(prepared, widthOfHello, _lineHeight);
      expect(withLines.lineCount, 1);
      expect(withLines.lines[0].text, 'Hello');
      expect(withLines.lines[0].width, widthOfHello);
    });

    test('breaks long words at grapheme boundaries', () {
      final prepared = prepareWithSegments('Superlongword', _style);
      final graphemeWidths = prepared.core.breakableWidths[0]!;
      final maxWidth =
          graphemeWidths[0] + graphemeWidths[1] + graphemeWidths[2] + 0.1;

      final plain = layout(prepared, maxWidth, _lineHeight);
      final rich = layoutWithLines(prepared, maxWidth, _lineHeight);

      expect(plain.lineCount, greaterThan(1));
      expect(rich.lineCount, plain.lineCount);
      expect(rich.height, plain.height);
      expect(rich.lines.map((l) => l.text).join(), 'Superlongword');
    });

    test('mixed-direction text is a stable smoke test', () {
      final prepared = prepareWithSegments(
        'According to \u0645\u062D\u0645\u062F \u0627\u0644\u0623\u062D\u0645\u062F, the results improved.',
        _style,
      );
      final result = layoutWithLines(prepared, 120, _lineHeight);

      expect(result.lineCount, greaterThanOrEqualTo(1));
      expect(result.height, result.lineCount * _lineHeight);
    });

    test('layoutNextLine reproduces layoutWithLines exactly', () {
      final prepared = prepareWithSegments(
        'The quick brown fox jumps over the lazy dog',
        _style,
      );
      const width = 120.0;
      final expected = layoutWithLines(prepared, width, _lineHeight);

      final actual = <LayoutLine>[];
      var cursor = const LayoutCursor(segmentIndex: 0, graphemeIndex: 0);
      while (true) {
        final line = layoutNextLine(prepared, cursor, width);
        if (line == null) break;
        actual.add(line);
        cursor = line.end;
      }

      expect(actual.length, expected.lines.length);
      for (int i = 0; i < actual.length; i++) {
        expect(actual[i].text, expected.lines[i].text);
        expect(actual[i].width, closeTo(expected.lines[i].width, 0.001));
        expect(actual[i].start, expected.lines[i].start);
        expect(actual[i].end, expected.lines[i].end);
      }
    });

    test('pre-wrap mode treats hard breaks as forced line boundaries', () {
      final prepared = prepareWithSegments(
        'a\nb',
        _style,
        whiteSpace: WhiteSpaceMode.preWrap,
      );
      final lines = layoutWithLines(prepared, 200, _lineHeight);
      expect(lines.lines.map((l) => l.text).toList(), ['a', 'b']);
      expect(layout(prepared, 200, _lineHeight).lineCount, 2);
    });

    test('pre-wrap mode treats tabs as hanging whitespace', () {
      final prepared = prepareWithSegments(
        'a\tb',
        _style,
        whiteSpace: WhiteSpaceMode.preWrap,
      );
      final spaceWidth = _measureWidth(' ', _fontSize);
      final prefixWidth = _measureWidth('a', _fontSize);
      final tabAdvance = _nextTabAdvance(prefixWidth, spaceWidth);
      final textWidth =
          prefixWidth + tabAdvance + _measureWidth('b', _fontSize);
      final width = textWidth - 0.1;

      final lines = layoutWithLines(prepared, width, _lineHeight);
      expect(lines.lines.map((l) => l.text).toList(), ['a\t', 'b']);
      expect(layout(prepared, width, _lineHeight).lineCount, 2);
    });

    test('pre-wrap mode keeps empty lines from consecutive hard breaks', () {
      final prepared = prepareWithSegments(
        '\n\n',
        _style,
        whiteSpace: WhiteSpaceMode.preWrap,
      );
      final lines = layoutWithLines(prepared, 200, _lineHeight);
      expect(lines.lines.map((l) => l.text).toList(), ['', '']);
      expect(layout(prepared, 200, _lineHeight).lineCount, 2);
    });

    test('pre-wrap does not invent extra trailing empty line', () {
      final prepared = prepareWithSegments(
        'a\n',
        _style,
        whiteSpace: WhiteSpaceMode.preWrap,
      );
      final lines = layoutWithLines(prepared, 200, _lineHeight);
      expect(lines.lines.map((l) => l.text).toList(), ['a']);
      expect(layout(prepared, 200, _lineHeight).lineCount, 1);
    });

    test('walkLineRanges reproduces layoutWithLines geometry', () {
      final prepared = prepareWithSegments(
        'The quick brown fox jumps over the lazy dog',
        _style,
      );
      const width = 120.0;
      final expected = layoutWithLines(prepared, width, _lineHeight);
      final actual = <LayoutLineRange>[];

      final lineCount = walkLineRanges(prepared, width, (line) {
        actual.add(line);
      });

      expect(lineCount, expected.lineCount);
      for (int i = 0; i < actual.length; i++) {
        expect(actual[i].width, closeTo(expected.lines[i].width, 0.001));
        expect(actual[i].start, expected.lines[i].start);
        expect(actual[i].end, expected.lines[i].end);
      }
    });

    test('countPreparedLines stays aligned with walked line counter', () {
      final texts = [
        'The quick brown fox jumps over the lazy dog.',
        'hello world test',
        'alpha\u200Bbeta gamma',
      ];
      final widths = [40.0, 80.0, 120.0, 200.0];

      for (final text in texts) {
        final prepared = prepareWithSegments(text, _style);
        for (final width in widths) {
          final counted = countPreparedLines(prepared.core, width);
          final walked = walkPreparedLines(prepared.core, width);
          expect(counted, walked,
              reason: 'Mismatch for "$text" at width $width');
        }
      }
    });
  });

  group('analysis unit tests', () {
    test('normalizeWhitespaceNormal collapses runs', () {
      expect(normalizeWhitespaceNormal('  Hello\t \n  World  '), 'Hello World');
    });

    test('normalizeWhitespaceNormal trims edges', () {
      expect(normalizeWhitespaceNormal('  hello  '), 'hello');
    });

    test('normalizeWhitespaceNormal preserves single spaces', () {
      expect(normalizeWhitespaceNormal('hello world'), 'hello world');
    });

    test('isCJK detects CJK characters', () {
      expect(isCJK('\u4E2D'), true); // 中
      expect(isCJK('\u3042'), true); // あ (hiragana)
      expect(isCJK('\uAC00'), true); // 가 (hangul)
      expect(isCJK('A'), false);
      expect(isCJK('1'), false);
    });

    test('isCJK detects astral CJK', () {
      expect(isCJK('\u{20000}'), true); // CJK Extension B
    });
  });
}
