#!/bin/sh
# PostToolUse hook: report shellcheck findings on the edited shell file; never modify it.
set -u

newline='
'

command -v jq >/dev/null 2>&1 || exit 0

report_context() {
	jq -n --arg context "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'
}

hook_input="$(cat)"
file_path="$(printf '%s' "$hook_input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file_path" in
*.sh | *.bash | *.bats) ;;
*) exit 0 ;;
esac
[ -f "$file_path" ] || exit 0

command -v shellcheck >/dev/null 2>&1 || exit 0

# no --severity: it empties the comment list and exits 0, looking like a clean run
shellcheck_json="$(shellcheck --format=json1 --exclude=SC1091 -- "$file_path" 2>/dev/null)"
shellcheck_exit=$?

if [ "$shellcheck_exit" -ge 2 ]; then
	report_context "devops-lsp: shellcheck could not scan ${file_path} (exit ${shellcheck_exit}), so the check did not happen. Treat this as unverified, not clean."
	exit 0
fi
[ "$shellcheck_exit" -eq 1 ] || exit 0

findings="$(printf '%s' "$shellcheck_json" |
	jq -r '(.comments // [])[]
	| select(.level != "style")
	| "\(.file):\(.line):\(.column): \(.level) SC\(.code) \(.message | gsub("[\\n\\r]+"; " "))"' 2>/dev/null || true)"
[ -n "$findings" ] || exit 0

report_context "devops-lsp: shellcheck reports findings on ${file_path}. Nothing is fixed automatically; fix them yourself:${newline}${findings}"
exit 0
