#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file" in
*.py | *.pyi) ;;
*) exit 0 ;;
esac
[ -f "$file" ] || exit 0

dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || exit 0

# Only touch projects that opted into ruff. Reformatting a repo that uses a different
# formatter would rewrite files nobody asked us to rewrite.
root=""
probe="$dir"
while [ -n "$probe" ] && [ "$probe" != "/" ]; do
	for cfg in ruff.toml .ruff.toml; do
		[ -f "$probe/$cfg" ] && root="$probe" && break 2
	done
	if [ -f "$probe/pyproject.toml" ] && grep -q '^\[tool\.ruff' "$probe/pyproject.toml" 2>/dev/null; then
		root="$probe"
		break
	fi
	probe="$(dirname "$probe")"
done
[ -n "$root" ] || exit 0

command -v ruff >/dev/null 2>&1 || exit 0

# --fix first (import order, unused imports, simple rewrites), then format.
(cd "$root" && ruff check --fix --quiet --no-cache "$file" >/dev/null 2>&1 || true)
(cd "$root" && ruff format --quiet --no-cache "$file" >/dev/null 2>&1 || true)

# Whatever ruff could not fix is still worth reporting.
left="$(cd "$root" && ruff check --quiet --no-cache --output-format concise "$file" 2>&1 || true)"
[ -n "$left" ] || exit 0

ctx="devops-lsp auto-heal ran 'ruff check --fix' and 'ruff format' on ${file}. Unresolved lint output below; address it:"$'\n'"$left"
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
