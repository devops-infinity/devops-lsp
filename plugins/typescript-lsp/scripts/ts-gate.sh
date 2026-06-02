#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[ -f "$root/tsconfig.json" ] || exit 0

changed="$(cd "$root" && git status --porcelain 2>/dev/null | grep -E '\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$' || true)"
[ -n "$changed" ] || exit 0

out="$(cd "$root" && npx --no-install tsc --noEmit -p tsconfig.json 2>&1 || true)"
printf '%s' "$out" | grep -qE 'error TS' || exit 0

reason="devops-lsp type-check gate: 'tsc --noEmit' reported errors. Fix them before finishing:"$'\n'"$out"
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
