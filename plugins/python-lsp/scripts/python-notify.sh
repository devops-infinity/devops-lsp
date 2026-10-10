#!/bin/sh
# PostToolUse hook: report ruff findings on the edited Python file; never modify it.
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
*.py | *.pyi) ;;
*) exit 0 ;;
esac
[ -f "$file_path" ] || exit 0

file_dir="$(cd "$(dirname -- "$file_path")" 2>/dev/null && pwd)" || exit 0

# only repos that opted into ruff; a repo standardized on another tool is left alone
ruff_root=""
walk_dir="$file_dir"
while [ -n "$walk_dir" ] && [ "$walk_dir" != "/" ]; do
	for config_name in ruff.toml .ruff.toml; do
		[ -f "$walk_dir/$config_name" ] && ruff_root="$walk_dir" && break 2
	done
	if [ -f "$walk_dir/pyproject.toml" ] && grep -q '^\[tool\.ruff' "$walk_dir/pyproject.toml" 2>/dev/null; then
		ruff_root="$walk_dir"
		break
	fi
	walk_dir="$(dirname -- "$walk_dir")"
done
[ -n "$ruff_root" ] || exit 0

command -v ruff >/dev/null 2>&1 || exit 0

ruff_output="$(cd "$ruff_root" && ruff check --quiet --no-cache --output-format concise "$file_path" 2>&1)"
ruff_exit=$?

if [ "$ruff_exit" -ge 2 ]; then
	report_context "devops-lsp: ruff could not run on ${file_path} (exit ${ruff_exit}). This is a tool or config problem, not a lint finding:${newline}${ruff_output}"
	exit 0
fi
[ "$ruff_exit" -eq 1 ] && [ -n "$ruff_output" ] || exit 0

report_context "devops-lsp: ruff reports findings on ${file_path}. Nothing is fixed automatically; fix them yourself:${newline}${ruff_output}"
exit 0
