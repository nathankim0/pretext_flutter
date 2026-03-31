# pretext_flutter

[![pub package](https://img.shields.io/pub/v/pretext_flutter.svg)](https://pub.dev/packages/pretext_flutter)

Pure Dart text measurement & layout library for Flutter. Port of [chenglou/pretext](https://github.com/chenglou/pretext).

Segments text once, caches segment widths, then performs **pure arithmetic** for layout at any width. No `TextPainter.layout()` on resize -- just cached widths and math.

**[Live Demo](https://nathankim0.github.io/pretext_flutter/)**

## Why?

Flutter's `TextPainter.layout()` cost is dominated by HarfBuzz text shaping, which is width-independent. This library caches shaped segment widths so relayout at different widths skips the expensive shaping step entirely.

**Use cases:**
- Pre-compute text heights for virtualized lists (chat, feeds)
- Paginate text in ebook/document viewers without repeated `TextPainter.layout()`
- Flow text around images/obstacles with variable-width lines
- Shrinkwrap: find the minimum container width for a given line count

## Installation

```yaml
dependencies:
  pretext_flutter: ^0.0.1
```

## Quick Start

```dart
import 'package:pretext_flutter/pretext_flutter.dart';

// 1. Prepare text once (segments + measures via TextPainter)
final style = TextStyle(fontSize: 16, fontFamily: 'Inter');
final prepared = prepare('AGI is here.', style);

// 2. Layout at any width (pure arithmetic, no TextPainter!)
final result = layout(prepared, 320, 20);
print('Height: ${result.height}, Lines: ${result.lineCount}');
```

`prepare()` does the one-time work: segment text, measure segments via TextPainter, cache widths. `layout()` is the cheap hot path: pure arithmetic over cached widths. On resize, only rerun `layout()`.

## API

### Lay out lines manually

```dart
final prepared = prepareWithSegments('Hello world!', style);
final result = layoutWithLines(prepared, 320, 20);
for (final line in result.lines) {
  print('${line.text} (width: ${line.width})');
}
```

### Flow text around obstacles

```dart
final prepared = prepareWithSegments(text, style);
var cursor = const LayoutCursor(segmentIndex: 0, graphemeIndex: 0);
double y = 0;

while (true) {
  final width = y < imageBottom ? columnWidth - imageWidth : columnWidth;
  final line = layoutNextLine(prepared, cursor, width);
  if (line == null) break;
  // Draw line.text at (0, y)
  cursor = line.end;
  y += lineHeight;
}
```

### Shrinkwrap (find tightest container width)

```dart
double maxW = 0;
walkLineRanges(prepared, 320, (line) {
  if (line.width > maxW) maxW = line.width;
});
// maxW is the widest line -- the tightest container width
```

## API Reference

| Function | Description |
|---|---|
| `prepare(text, style)` | One-time text analysis + measurement. Returns opaque handle. |
| `prepareWithSegments(text, style)` | Same as `prepare()` but exposes segment data for custom rendering. |
| `layout(prepared, maxWidth, lineHeight)` | Pure arithmetic layout. Returns `{lineCount, height}`. |
| `layoutWithLines(prepared, maxWidth, lineHeight)` | Layout with per-line text, width, and cursor details. |
| `walkLineRanges(prepared, maxWidth, onLine)` | Non-materializing line geometry pass (for shrinkwrap). |
| `layoutNextLine(prepared, cursor, maxWidth)` | Iterator API for variable-width layout (text around obstacles). |
| `clearCache()` | Clear all cached segment widths. |

## Demos

See the [live demo](https://nathankim0.github.io/pretext_flutter/) or run locally:

```bash
cd example
flutter run -d chrome
```

- **Editorial Engine** -- Multi-column text reflow around draggable animated orbs at 60fps
- **Bubbles** -- Chat bubble shrinkwrap comparison showing wasted space reduction

## Supported text features

- CJK line breaking with kinsoku rules (Japanese/Chinese/Korean)
- Punctuation attachment ("hello." measured as one unit)
- Trailing whitespace hanging (CSS behavior)
- overflow-wrap: break-word at grapheme boundaries
- Soft hyphen support
- URL and numeric run merging
- Arabic/Myanmar/Devanagari punctuation rules
- `pre-wrap` mode for preserved spaces, tabs, and hard breaks

## Credits

Based on [pretext](https://github.com/chenglou/pretext) by Cheng Lou, which builds on Sebastian Markbage's [text-layout](https://github.com/chenglou/text-layout) research.

## License

MIT
