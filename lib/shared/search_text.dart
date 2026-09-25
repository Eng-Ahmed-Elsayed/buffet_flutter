/// Folds text for matching, so what a person types finds what an admin typed.
///
/// Arabic is written with several interchangeable letter forms, and a phone
/// keyboard makes some easier to reach than others. Without folding, «قهوه»
/// misses «قهوة» and «اسبرسو» misses «إسبرسو». Folded:
/// - alef with hamza or madda (أ إ آ) and wasla (ٱ) → bare alef (ا);
/// - teh marbuta (ة) → heh (ه);
/// - alef maqsura (ى) → yeh (ي);
/// - tashkeel (the short-vowel marks) and tatweel (ـ) are dropped;
/// - Latin is lower-cased, and runs of whitespace collapse to one space.
String foldForSearch(String input) {
  final out = StringBuffer();
  var lastWasSpace = true;
  for (final rune in input.toLowerCase().runes) {
    // Tashkeel U+064B–U+0652, superscript alef U+0670, tatweel U+0640.
    if ((rune >= 0x064B && rune <= 0x0652) ||
        rune == 0x0670 ||
        rune == 0x0640) {
      continue;
    }
    final folded = switch (rune) {
      0x0623 || 0x0625 || 0x0622 || 0x0671 => 0x0627, // أ إ آ ٱ → ا
      0x0629 => 0x0647, // ة → ه
      0x0649 => 0x064A, // ى → ي
      _ => rune,
    };
    final isSpace = folded == 0x20 || folded == 0x09 || folded == 0x0A;
    if (isSpace) {
      if (!lastWasSpace) out.write(' ');
      lastWasSpace = true;
    } else {
      out.writeCharCode(folded);
      lastWasSpace = false;
    }
  }
  return out.toString().trimRight();
}

/// Whether [query] matches any of [fields], after folding. An empty query
/// matches everything.
bool matchesSearch(String query, Iterable<String> fields) {
  final q = foldForSearch(query);
  if (q.isEmpty) return true;
  return fields.any((f) => foldForSearch(f).contains(q));
}
