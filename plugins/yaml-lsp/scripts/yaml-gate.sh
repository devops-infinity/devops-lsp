#!/bin/sh
# Whole-project yamllint plus prettier gate: block with the problems they report; a run that cannot happen is never read as a pass.
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
	block_with_reason "devops-lsp YAML gate: git could not list the changed files, so the check did not happen. Treat this as unverified, not clean."
	exit 0
fi
# POSIX sh has no NUL-safe string handling; filenames containing a newline are outside this line protocol
tr '\0' '\n' <"$git_nul_file" >"$scratch_file"

set --
while IFS= read -r rel_path; do
	[ -n "$rel_path" ] || continue
	[ -f "$repo_root/$rel_path" ] || continue
	case "$rel_path" in
	*.yaml | *.yml) set -- "$@" "$rel_path" ;;
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

problems=""

default_config='{
  extends: default,
  rules: {
    braces: {min-spaces-inside: 0, max-spaces-inside: 1},
    comments: {min-spaces-from-content: 1},
    comments-indentation: disable,
    document-start: disable,
    line-length: {max: 160},
    octal-values: {forbid-implicit-octal: true, forbid-explicit-octal: true}
  }
}'

yamllint_bin="$(resolve_tool yamllint)"
if [ -n "$yamllint_bin" ]; then
	yamllint_config=""
	for config_name in .yamllint .yamllint.yaml .yamllint.yml; do
		if [ -f "$repo_root/$config_name" ]; then
			yamllint_config="$repo_root/$config_name"
			break
		fi
	done
	if [ -n "$yamllint_config" ]; then
		yamllint_output="$(cd "$repo_root" && "$yamllint_bin" -c "$yamllint_config" -- "$@" 2>&1)"
	else
		yamllint_output="$(cd "$repo_root" && "$yamllint_bin" -d "$default_config" -- "$@" 2>&1)"
	fi
	yamllint_exit=$?
	# yamllint above 1 is a usage or I/O failure, so an empty result would read as clean
	if [ "$yamllint_exit" -ge 2 ]; then
		problems="${problems}yamllint exited ${yamllint_exit}, so the lint did not run. Treat this as unverified, not clean:${newline}${yamllint_output}${newline}"
	elif [ -n "$yamllint_output" ]; then
		problems="${problems}${yamllint_output}${newline}"
	fi
fi

prettier_bin="$(resolve_tool prettier)"
if [ -n "$prettier_bin" ]; then
	# prettier exits 2 for both a parse error and a tool failure, so its output, not the code, carries the distinction
	if ! prettier_output="$(cd "$repo_root" && "$prettier_bin" --check -- "$@" 2>&1)"; then
		problems="${problems}${prettier_output}${newline}"
	fi
fi

[ -n "$problems" ] || exit 0

block_with_reason "devops-lsp YAML gate: yamllint or 'prettier --check' reported problems. Fix them before finishing:${newline}${problems}"
exit 0
