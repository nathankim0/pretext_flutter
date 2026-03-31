## pretext_flutter

Flutter/Dart port of [chenglou/pretext](https://github.com/chenglou/pretext).
Internal notes for contributors and agents. Use `README.md` as the public source of truth for API examples and user-facing limitations.

### Commands

```bash
# Run tests
flutter test

# Static analysis
dart analyze lib/

# Dry-run publish check
dart pub publish --dry-run

# Run example app
cd example && flutter run
```

### Important files

- `pubspec.yaml` — package metadata, dependencies, SDK constraints
- `lib/pretext_flutter.dart` — public API surface: `prepare()`, `layout()`, `layoutWithLines()`, `walkLineRanges()`, `layoutNextLine()`, `clearCache()`; also contains the internal `_measureAnalysis()` and line-text materialization helpers
- `lib/src/analysis.dart` — normalization, word segmentation (custom Dart implementation replacing `Intl.Segmenter`), CJK/kinsoku rules, punctuation merging, URL/numeric run merging, and the full text-analysis pipeline
- `lib/src/measurement.dart` — `TextPainter`-based segment measurement with `Map<TextStyle, Map<String, double>>` cache; replaces the original's Canvas `measureText()` + emoji correction
- `lib/src/line_break.dart` — internal line-walking core shared by the rich layout APIs and the hot-path line counter; includes both simple (normal text) and full (soft-hyphen, tabs, pre-wrap) walkers
- `lib/src/types.dart` — all public and internal types: `PreparedText`, `PreparedCore`, `LayoutResult`, `LayoutLine`, `LayoutCursor`, `SegmentBreakKind`, etc.
- `test/` — unit and integration tests
- `example/` — Flutter example app demonstrating all public APIs

### Implementation notes

- This is a **Flutter port**, not a 1:1 translation. Browser-specific code has been removed; Flutter-native measurement has been substituted.
- `prepare()` / `prepareWithSegments()` do horizontal-only work. `layout()` / `layoutWithLines()` take explicit `lineHeight`.
- `prepare()` should stay the opaque fast-path handle. If a caller needs segment arrays, that should flow through `prepareWithSegments()` instead of re-exposing internals on the main prepared type.
- `walkLineRanges()` is the rich-path batch geometry API: no string materialization, but still line widths/cursors/discretionary-hyphen state. Prefer it over private line walkers for shrinkwrap or aggregate layout work.
- `prepare()` is internally split into a text-analysis phase and a measurement phase; keep that seam clear, but keep the public API simple unless requirements force a change.
- The internal segment model distinguishes eight break kinds: normal text, collapsible spaces, preserved spaces, tabs, non-breaking glue (`NBSP` / `NNBSP` / `WJ`-like runs), zero-width break opportunities, soft hyphens, and hard breaks. Do not collapse those back into one boolean.
- `layout()` is the resize hot path: no TextPainter calls, no string work, and avoid gratuitous allocations.
- Segment width cache is `Map<TextStyle, Map<String, double>>`; shared across texts and resettable via `clearCache()`.
- Word segmentation uses a custom Dart implementation with the `characters` package for grapheme iteration. This replaces the browser's `Intl.Segmenter` which is not available in Dart.
- Punctuation is merged into preceding word-like segments only, never into spaces.
- Keep script-specific break-policy fixes in preprocessing (analysis.dart), not `layout()`. That includes Arabic no-space punctuation clusters, Arabic punctuation-plus-mark clusters, and `" " + combining marks` before Arabic text.
- `NBSP`-style glue should survive `prepare()` as visible content and prevent ordinary word-boundary wrapping; `ZWSP` should survive as a zero-width break opportunity.
- Soft hyphens should stay invisible when unbroken, but if the engine chooses that break, the broken line should expose a visible trailing hyphen in `layoutWithLines()`.
- `layoutNextLine()` is the rich-path escape hatch for variable-width userland layout. Keep its internal split semantically aligned with `layoutWithLines()`, but do not pull its extra bookkeeping into the hot `layout()` path.
- Astral CJK ideographs, compatibility ideographs, and the later extension blocks must still hit the CJK path; do not rely on BMP-only code unit checks there. Use `String.runes` for code point iteration.
- CJK grapheme splitting plus kinsoku merging keeps prohibited punctuation attached to adjacent graphemes.
- Supported layout target: `white-space: normal`, `word-break: normal`, `overflow-wrap: break-word`, `line-break: auto` equivalent. Narrow widths may still break inside words, but only at grapheme boundaries.
- There is a second explicit whitespace mode, `WhiteSpaceMode.preWrap`, for ordinary spaces, `\t` tabs, and `\n` hard breaks. Tabs follow the default 8-space tab stops.
- Line-fit tolerance is a fixed `0.005` (no browser-specific values needed in Flutter).
- `AnalysisProfile.carryCJKAfterClosingQuote` defaults to `false`. The original sets this to `true` for Chromium browsers; since Flutter is not a browser, we default to the non-Chromium behavior.

### What was dropped from the original

- `bidi.ts` — Flutter's text engine handles bidi natively; no need for custom bidi metadata.
- Emoji correction — `TextPainter` returns accurate widths unlike browser Canvas at small font sizes.
- Engine profile / browser sniffing — no `navigator.userAgent`, no Safari/Chrome-specific epsilon or shims.
- `setLocale()` — Dart's word segmentation is custom-built, not backed by `Intl.Segmenter`. Locale-sensitive word breaking (Thai, Khmer, etc.) may need future work.
- Canvas context management — replaced entirely by `TextPainter`.
- Browser accuracy/corpus/benchmark checker infrastructure — not applicable to Flutter.

### Known limitations

- Word segmentation for Thai, Lao, Khmer, Myanmar, and other scripts that don't use spaces between words may not match browser-level ICU segmentation. The custom segmenter splits on grapheme boundaries, which is correct but less granular than ICU word boundaries.
- `TextPainter` measurement requires a Flutter binding (cannot run in pure Dart without `WidgetsFlutterBinding.ensureInitialized()`). Tests must use `TestWidgetsFlutterBinding`.
- No runtime calibration of line-fit tolerance. The fixed `0.005` may need adjustment for specific rendering backends.

### Open questions

- Should word segmentation be improved with a port of ICU word boundary rules for Southeast Asian scripts?
- Should `setLocale()` be reintroduced once better Dart word segmentation is available?
- Should `AnalysisProfile` be exposed publicly for advanced users who want to customize CJK behavior?
- ASCII fast path could skip CJK and emoji overhead for pure-ASCII text.
- Additional layout modes (break-all, keep-all) are untested.

### Related

- [chenglou/pretext](https://github.com/chenglou/pretext) — the original TypeScript library
- [text-layout](https://github.com/chenglou/text-layout) — Sebastian Markbage's original prototype
