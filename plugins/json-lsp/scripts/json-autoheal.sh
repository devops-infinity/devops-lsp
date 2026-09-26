#!/bin/sh
set -u

nl='
'

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file" in
*.json | *.jsonc) ;;
*) exit 0 ;;
esac
[ -f "$file" ] || exit 0

dir="$(cd "$(dirname -- "$file")" 2>/dev/null && pwd)" || exit 0
root="$(cd "$dir" && { git rev-parse --show-toplevel 2>/dev/null || pwd; })"
[ -n "${root:-}" ] || exit 0

bin() {
	if [ -x "$root/node_modules/.bin/$1" ]; then
		printf '%s' "$root/node_modules/.bin/$1"
	elif command -v "$1" >/dev/null 2>&1; then
		command -v "$1"
	fi
}

p="$(bin prettier)"
[ -n "$p" ] || exit 0

if ! out="$(cd "$root" && "$p" --write "$file" 2>&1)"; then
	ctx="devops-lsp auto-heal ran 'prettier --write' on ${file} and it failed. The file does not parse as JSON; fix it and it formats on the next edit:${nl}${out}"
	jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
fi
exit 0
