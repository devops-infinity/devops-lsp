#!/bin/sh
# PostToolUse hook: report a php -l parse error on the edited PHP file; never modify it.
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
*.blade.php) exit 0 ;;
*.php | *.phtml | *.php3 | *.php4 | *.php5 | *.php7 | *.php8 | *.phps) ;;
*) exit 0 ;;
esac
[ -f "$file_path" ] || exit 0

command -v php >/dev/null 2>&1 || exit 0

if ! lint_output="$(php -l "$file_path" 2>&1)"; then
	report_context "devops-lsp: 'php -l' found a syntax error in ${file_path}. Nothing is fixed automatically; fix it yourself:${newline}${lint_output}"
fi
exit 0
