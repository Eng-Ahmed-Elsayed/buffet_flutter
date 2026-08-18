#!/usr/bin/env bash
# PostToolUse guard for Dart edits in the Digital Buffet client.
# Flags the mechanical violations of CLAUDE.md's domain rules.
# Advisory only: exit 2 surfaces feedback to Claude, it does not block the edit.

file=$(printf '%s' "${CLAUDE_TOOL_INPUT:-}" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -z "$file" ] && exit 0
case "$file" in
  *.dart) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] && [ -r "$file" ] || exit 0
case "$file" in
  *.g.dart|*.freezed.dart) exit 0 ;;
esac

warn=""
add() { warn="${warn}  - $1"$'\n'; }

# RTL: directional-agnostic APIs only (CLAUDE.md rule 6)
grep -nE 'EdgeInsets\.only\([^)]*(left|right):' "$file" >/dev/null 2>&1 &&
  add "EdgeInsets.only(left:/right:) — use EdgeInsetsDirectional.only(start:/end:)"
grep -nE '\b(Alignment\.(centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight))' "$file" >/dev/null 2>&1 &&
  add "Alignment.*Left/Right — use AlignmentDirectional (start/end)"
grep -nE 'TextAlign\.(left|right)' "$file" >/dev/null 2>&1 &&
  add "TextAlign.left/right — use TextAlign.start/end"

# Theme tokens, not literals (CLAUDE.md "Theme tokens")
case "$file" in
  */theme/*) ;;
  *) grep -nE 'Color\(0x[0-9a-fA-F]{8}\)' "$file" >/dev/null 2>&1 &&
       add "literal Color(0xFF…) outside lib/theme/ — use a BrandColors token" ;;
esac

# Order status by name, never ordinal (CLAUDE.md rule 5; Ready = 4)
grep -nE 'status[A-Za-z]*[[:space:]]*[=!]=[[:space:]]*[0-9]' "$file" >/dev/null 2>&1 &&
  add "order status compared to an integer — compare the string name (Ready = 4, out of order)"

# Token storage (CLAUDE.md "Stack decisions")
grep -n 'SharedPreferences' "$file" >/dev/null 2>&1 &&
  grep -niE 'token|jwt|bearer' "$file" >/dev/null 2>&1 &&
  add "token near SharedPreferences — the JWT belongs in flutter_secure_storage only"

# Shortages warn, never block (CLAUDE.md rule 2)
grep -niE '(onPressed|onTap)[[:space:]]*:[[:space:]]*null' "$file" >/dev/null 2>&1 &&
  grep -niE 'shortage|warning|stock|servingsLeft' "$file" >/dev/null 2>&1 &&
  add "control disabled in a file mentioning stock/shortage — shortages warn, never block"

if [ -n "$warn" ]; then
  printf 'Domain-rule check on %s:\n%s\nSee CLAUDE.md. Fix these unless deliberate.\n' "$file" "$warn" >&2
  exit 2
fi
exit 0
