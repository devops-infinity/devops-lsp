#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

changed="$(cd "$root" && git status --porcelain 2>/dev/null |
	sed -E 's/^.{3}//; s/^.* -> //; s/^"(.*)"$/\1/' | grep -E '\.(sh|bash|bats)$' || true)"
[ -n "$changed" ] || exit 0

command -v shellcheck >/dev/null 2>&1 || exit 0

files=""
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	[ -f "$root/$rel" ] || continue
	files="$files$root/$rel"$'\n'
done <<EOF
$changed
EOF
[ -n "$files" ] || exit 0

# The linter's own exit code is non-zero for warnings too, so severity is read from
# the JSON instead. Only real errors block; warnings are counted and reported.
out="$(printf '%s' "$files" | grep -v '^$' | tr '\n' '\0' |
	xargs -0 shellcheck --format=json1 2>/dev/null || true)"
[ -n "$out" ] || exit 0

errors="$(printf '%s' "$out" | jq -r '
  (.comments // [])[]
  | select(.level == "error")
  | "\(.file):\(.line):\(.column): SC\(.code) \(.message)"
' 2>/dev/null | awk '!seen[$0]++' || true)"

warncount="$(printf '%s' "$out" | jq -r '[(.comments // [])[] | select(.level == "warning")] | length' 2>/dev/null || echo 0)"

[ -n "$errors" ] || exit 0

total="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
shown="$(printf '%s\n' "$errors" | head -40)"
[ "$total" -gt 40 ] && shown="$shown"$'\n'"... $((total - 40)) more"

reason="devops-lsp shell gate: shellcheck reported ${total} error(s). Fix them before finishing:"$'\n'"$shown"
[ "${warncount:-0}" -gt 0 ] && reason="$reason"$'\n\n'"There are also ${warncount} shellcheck warning(s)."

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
