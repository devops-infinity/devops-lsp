#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file" in
*.sh | *.bash | *.bats) ;;
*) exit 0 ;;
esac
[ -f "$file" ] || exit 0

dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || exit 0
base="$(basename "$file")"

# Step 1: apply the linter's own fixes. It only emits replacements for rules with an
# unambiguous correction - quoting an expansion, adding `|| exit` to a bare cd - and
# leaves anything needing human judgement alone, so this is safe to run unattended.
# Invoked with a bare filename so the diff carries a/ and b/ prefixes that apply cleanly.
if command -v shellcheck >/dev/null 2>&1; then
	diff_out="$(cd "$dir" && shellcheck --format=diff "$base" 2>/dev/null || true)"
	if [ -n "$diff_out" ]; then
		if ! printf '%s\n' "$diff_out" | (cd "$dir" && git apply - 2>/dev/null); then
			printf '%s\n' "$diff_out" | (cd "$dir" && patch -p1 -s >/dev/null 2>&1 || true)
		fi
	fi
fi

# Step 2: format. Bare `shfmt --write` is deliberate - passing any parser or printer
# flag (-i, -ln, -s, -bn ...) makes shfmt discard .editorconfig entirely, so a repo
# that declares its own shell style would silently lose it.
if command -v shfmt >/dev/null 2>&1; then
	err="$(shfmt --write "$file" 2>&1 || true)"
	if [ -n "$err" ]; then
		ctx="devops-lsp auto-heal ran 'shfmt --write' on ${file} and it failed to parse. Fix the syntax:"$'\n'"$err"
		jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
		exit 0
	fi
fi

command -v shellcheck >/dev/null 2>&1 || exit 0

# Step 3: report what is left. Style-level findings are excluded - that tier is
# taste (brace-everything, prefer [[ ]]) and is where the false positives live.
left="$(cd "$dir" && shellcheck --format=json1 --exclude=SC1091 "$base" 2>/dev/null |
	jq -r '(.comments // [])[] | select(.level != "style") | "\(.file):\(.line):\(.column): \(.level) SC\(.code) \(.message)"' 2>/dev/null || true)"
[ -n "$left" ] || exit 0

ctx="devops-lsp auto-heal fixed and formatted ${file}. shellcheck still reports the following; address it:"$'\n'"$left"
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
