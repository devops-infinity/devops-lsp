#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file" in
*.sh | *.bash | *.bats) ;;
*) exit 0 ;;
esac
[ -f "$file" ] || exit 0

command -v shfmt >/dev/null 2>&1 || exit 0

# shfmt reads .editorconfig on its own, so a project that declares indent_style or
# indent_size for shell keeps its own house style without any flags from us.
err="$(shfmt --write "$file" 2>&1 || true)"
if [ -n "$err" ]; then
	ctx="devops-lsp auto-heal ran 'shfmt --write' on ${file} and it failed to parse. Fix the syntax:"$'\n'"$err"
	jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
	exit 0
fi

command -v shellcheck >/dev/null 2>&1 || exit 0

left="$(shellcheck --format=gcc "$file" 2>/dev/null || true)"
[ -n "$left" ] || exit 0

ctx="devops-lsp auto-heal formatted ${file} with shfmt. shellcheck still reports the following; address it:"$'\n'"$left"
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
