#!/bin/sh
# PostToolUse hook: report a prettier --check failure on the edited YAML file; never modify it.
set -u

newline='
'

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

report_context() {
	jq -n --arg context "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'
}

hook_input="$(cat)"
file_path="$(printf '%s' "$hook_input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file_path" in
*.yaml | *.yml) ;;
*) exit 0 ;;
esac
[ -f "$file_path" ] || exit 0

file_dir="$(cd "$(dirname -- "$file_path")" 2>/dev/null && pwd)" || exit 0
repo_root="$(cd "$file_dir" && { git rev-parse --show-toplevel 2>/dev/null || pwd; })"
[ -n "${repo_root:-}" ] || exit 0

resolve_tool() {
	if [ -x "$repo_root/node_modules/.bin/$1" ]; then
		printf '%s' "$repo_root/node_modules/.bin/$1"
	elif command -v "$1" >/dev/null 2>&1; then
		command -v "$1"
	fi
}

prettier_bin="$(resolve_tool prettier)"
[ -n "$prettier_bin" ] || exit 0

if ! prettier_output="$(cd "$repo_root" && "$prettier_bin" --check -- "$file_path" 2>&1)"; then
	report_context "devops-lsp: 'prettier --check' found a problem in ${file_path}: the file does not parse as YAML, or it is not formatted canonically. Nothing is fixed automatically; fix it yourself:${newline}${prettier_output}"
fi
exit 0
