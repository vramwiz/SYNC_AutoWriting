# Stroke reference data / 書き順参照データ

`StrokeReference.bin` and the generated `.inc` files are data licensed under
Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0).
https://creativecommons.org/licenses/by-sa/3.0/
Full text: `../../ThirdParty/LICENSE.CC-BY-SA-3.0.txt`.
These data can be copied, extracted, adapted and redistributed under that licence;
no additional restriction or technical protection is applied to them.

Original work: **KanjiVG**, Copyright © 2009–2026 **Ulrich Apel**.
https://kanjivg.tagaini.net/ / https://github.com/KanjiVG/kanjivg

Intermediate derivative: **fude-kana-data**, published by **Karim Ghezali**.
https://github.com/karimghezali/fude-kana-data
Pinned commit: `ab69a27e2f5a5125ac89b5f13a1b0f0e318d5319`.
Original upstream notices and licence are preserved in `UPSTREAM-NOTICE.txt`
and `UPSTREAM-LICENSE.txt`. Neither original author endorses this plugin.

Further adaptation: **SYNC_AutoWriting stroke reference**,
Copyright © 2026 **VRAMの魔術師**, CC BY-SA 3.0.
Changes: the 176 kana JSON records are resampled by arc length, quantised to
unsigned 16-bit coordinates, sorted by Unicode scalar value and encoded into
the AWSTREF1 binary format. Original kana stroke count, order and direction
are retained. Small kana and voiced/semi-voiced forms remain separate entries.
The index and per-file hashes are recorded in `Manifest.json`.

A–Z, a–z and 0–9 (62 characters) are independently authored representative
manuscript paths, also offered under CC BY-SA 3.0. They are not extracted from
any font or handwriting dataset and are not a claim of a unique writing standard.
For example A has three strokes; B/D/P/R start with a downward stem; i/j put
the dot after the body; a/g use single-storey manuscript forms. A font whose
shape is incompatible with these forms retains the legacy estimate.

No font files, font outlines, glyph masks or user learning are contained here.
The runtime code is separately licensed as GPL-3.0-only; these data retain
their CC BY-SA 3.0 licence, including when embedded in the AUF2.

## Rebuild (development only)

Download the archive of the pinned commit above, verify its SHA-256 against
`Manifest.json`, and extract it. With Node.js 24 or later:

```text
node Tools/build_stroke_reference.mjs <extracted-fude-kana-data-directory>
```

The converter uses only Node.js built-ins. No Node.js, Python, network access
or per-character JSON loading is used by the plugin at runtime. The packaged
`.bin` is the exact same byte sequence compiled into the AUF2. The runtime
uses its immutable embedded copy; editing the packaged file does not alter it.

## AWSTREF1 format (little endian)

Header: 8 ASCII bytes `AWSTREF1`, uint32 entry count, uint32 total byte length.
Sorted directory: uint32 Unicode codepoint, uint32 absolute payload offset,
uint32 payload length, uint32 source (1 = kana derivative, 2 = manuscript Latin).
Each payload starts with uint16 stroke count. Each ordered stroke has uint16
flags (bit 0 = upstream curl indication), uint16 point count, then uint16 x/y
pairs in [0, 65535]. First/last points are start/end; point order is direction.
The format uses 32-bit codepoints to permit a future kanji expansion. This
release contains only the 238 entries described above.
