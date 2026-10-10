#!/bin/sh
# Whole-project prettier gate: block with the problems it reports; a run that cannot happen is never read as a pass.
set -u

newline='
'

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

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

git_nul_file="$(mktemp)" || exit 0
scratch_file="$(mktemp)" || exit 0
trap 'rm -f "$git_nul_file" "$scratch_file"' EXIT HUP INT TERM

if ! (cd "$repo_root" && {
	git diff --name-only -z || exit 1
	git diff --name-only --cached -z || exit 1
	git ls-files --others --exclude-standard -z || exit 1
} 2>/dev/null) >"$git_nul_file"; then
	block_with_reason "devops-lsp JSON gate: git could not list the changed files, so the check did not happen. Treat this as unverified, not clean."
	exit 0
fi
# POSIX sh has no NUL-safe string handling; filenames containing a newline are outside this line protocol
tr '\0' '\n' <"$git_nul_file" >"$scratch_file"

set --
while IFS= read -r rel_path; do
	[ -n "$rel_path" ] || continue
	[ -f "$repo_root/$rel_path" ] || continue
	case "$rel_path" in
	*.json | *.jsonc) set -- "$@" "$rel_path" ;;
	esac
done <"$scratch_file"
[ "$#" -gt 0 ] || exit 0

resolve_tool() {
	if [ -x "$repo_root/node_modules/.bin/$1" ]; then
		printf '%s' "$repo_root/node_modules/.bin/$1"
	elif command -v "$1" >/dev/null 2>&1; then
		command -v "$1"
	fi
}

prettier_bin="$(resolve_tool prettier)"
[ -n "$prettier_bin" ] || exit 0

# prettier exits 2 for both a parse error and a tool failure, so its output, not the code, carries the distinction
prettier_output="$(cd "$repo_root" && "$prettier_bin" --check -- "$@" 2>&1)"
prettier_exit=$?
[ "$prettier_exit" -eq 0 ] && exit 0

block_with_reason "devops-lsp JSON gate: 'prettier --check' found unformatted or unparseable JSON. Fix it before finishing:${newline}${prettier_output}"
exit 0
