#!/bin/sh
# Whole-project tsc gate: block with the errors it reports; a tsc that cannot run is never read as a pass.
set -u

newline='
'

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
command -v npx >/dev/null 2>&1 || exit 0

if [ -t 0 ]; then
	printf 'usage: echo ...hook JSON... | %s\n' "$0" >&2
	exit 0
fi

block_with_reason() {
	jq -n --arg reason "$1" '{decision: "block", reason: $reason}'
}

hook_input="$(cat)"
stop_hook_active="$(printf '%s' "$hook_input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$stop_hook_active" = "true" ] && exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[ -f "$repo_root/tsconfig.json" ] || exit 0

git_nul_file="$(mktemp)" || exit 0
scratch_file="$(mktemp)" || exit 0
trap 'rm -f "$git_nul_file" "$scratch_file"' EXIT HUP INT TERM

if ! (cd "$repo_root" && {
	git diff --name-only -z || exit 1
	git diff --name-only --cached -z || exit 1
	git ls-files --others --exclude-standard -z || exit 1
} 2>/dev/null) >"$git_nul_file"; then
	block_with_reason "devops-lsp type-check gate: git could not list the changed files, so the check did not happen. Treat this as unverified, not clean."
	exit 0
fi
# POSIX sh has no NUL-safe string handling; filenames containing a newline are outside this line protocol
tr '\0' '\n' <"$git_nul_file" >"$scratch_file"

changed_files=""
while IFS= read -r rel_path; do
	[ -n "$rel_path" ] || continue
	[ -f "$repo_root/$rel_path" ] || continue
	case "$rel_path" in
	*.ts | *.tsx | *.mts | *.cts | *.js | *.jsx | *.mjs | *.cjs) changed_files="${changed_files}${rel_path}${newline}" ;;
	esac
done <"$scratch_file"
[ -n "$changed_files" ] || exit 0

# an unresolvable tsc writes nothing, and grepping that reports the project clean
if ! (cd "$repo_root" && npx --no-install tsc --version >/dev/null 2>&1); then
	block_with_reason "devops-lsp type-check gate: 'npx --no-install tsc' could not run, so the type check did not happen. Install typescript in this project. Treat this as unverified, not clean."
	exit 0
fi

tsc_output="$(cd "$repo_root" && npx --no-install tsc --noEmit -p tsconfig.json 2>&1)"
tsc_exit=$?
[ "$tsc_exit" -eq 0 ] && exit 0

block_with_reason "devops-lsp type-check gate: 'tsc --noEmit' reported problems (exit ${tsc_exit}). Fix them before finishing:${newline}${tsc_output}"
exit 0
