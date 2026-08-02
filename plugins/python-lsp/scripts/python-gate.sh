#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

changed="$(cd "$root" && git status --porcelain 2>/dev/null |
	sed -E 's/^.{3}//; s/^.* -> //; s/^"(.*)"$/\1/' | grep -E '\.pyi?$' || true)"
[ -n "$changed" ] || exit 0

command -v basedpyright >/dev/null 2>&1 || exit 0

# Every Python project touched by a changed file. A project does not have to sit at the
# git root, and one repo can hold several, so resolve them from the files themselves.
projects="$(printf '%s\n' "$changed" | while IFS= read -r rel; do
	dir="$root/$(dirname "$rel")"
	[ -d "$dir" ] || continue
	probe="$(cd "$dir" && pwd)"
	while [ -n "$probe" ] && [ "$probe" != "/" ]; do
		for marker in pyproject.toml setup.py setup.cfg; do
			if [ -f "$probe/$marker" ]; then
				printf '%s\n' "$probe"
				break 3
			fi
		done
		probe="$(dirname "$probe")"
	done
done | sort -u)"
[ -n "$projects" ] || exit 0

errors=""
while IFS= read -r proj; do
	[ -n "$proj" ] || continue
	out="$(cd "$proj" && basedpyright --outputjson 2>/dev/null || true)"
	[ -n "$out" ] || continue
	found="$(printf '%s' "$out" | jq -r '
    (.generalDiagnostics // [])[]
    | select(.severity == "error")
    | "\(.file):\((.range.start.line // 0) + 1):\((.range.start.character // 0) + 1): \(.message | split("\n")[0])"
  ' 2>/dev/null || true)"
	[ -n "$found" ] && errors="$errors$found"$'\n'
done <<EOF
$projects
EOF

errors="$(printf '%s' "$errors" | grep -v '^$' | awk '!seen[$0]++' || true)"
[ -n "$errors" ] || exit 0

total="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
shown="$(printf '%s\n' "$errors" | head -40)"
[ "$total" -gt 40 ] && shown="$shown"$'\n'"... $((total - 40)) more"

reason="devops-lsp Python gate: basedpyright reported ${total} error(s). Fix them before finishing:"$'\n'"$shown"
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
