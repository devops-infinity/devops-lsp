#!/bin/sh
# PostToolUse hook: report eslint findings on the edited TS/JS file; never modify it.
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
*.ts | *.tsx | *.mts | *.cts | *.js | *.jsx | *.mjs | *.cjs) ;;
*) exit 0 ;;
esac
[ -f "$file_path" ] || exit 0

file_dir="$(dirname -- "$file_path")"
repo_root="$(cd "$file_dir" 2>/dev/null && { git rev-parse --show-toplevel 2>/dev/null || pwd; })"
[ -n "${repo_root:-}" ] || exit 0

has_eslint_config=""
for config_name in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml; do
	if [ -f "$repo_root/$config_name" ]; then
		has_eslint_config=1
		break
	fi
done
[ -n "$has_eslint_config" ] || exit 0

command -v npx >/dev/null 2>&1 || exit 0

eslint_output="$(cd "$repo_root" && npx --no-install eslint "$file_path" 2>&1)"
eslint_exit=$?

if [ "$eslint_exit" -ge 2 ]; then
	report_context "devops-lsp: eslint could not run on ${file_path} (exit ${eslint_exit}). This is a tool or config problem, not a lint finding:${newline}${eslint_output}"
	exit 0
fi
[ "$eslint_exit" -eq 1 ] && [ -n "$eslint_output" ] || exit 0

case "$eslint_output" in
*"ould not determine executable"* | *"command not found"* | *"npm error"* | *"npm ERR"*)
	report_context "devops-lsp: eslint could not run on ${file_path}; npx could not find the project's eslint. This is a tool problem, not a lint finding:${newline}${eslint_output}"
	exit 0
	;;
esac

report_context "devops-lsp: eslint reports findings on ${file_path}. Nothing is fixed automatically; fix them yourself:${newline}${eslint_output}"
exit 0
