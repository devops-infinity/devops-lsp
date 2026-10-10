#!/bin/sh
# Whole-project shellcheck gate: block with the findings it reports; a scan that cannot happen is never read as a pass.
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
	block_with_reason "devops-lsp shell gate: git could not list the changed files, so the check did not happen. Treat this as unverified, not clean."
	exit 0
fi
# POSIX sh has no NUL-safe string handling; filenames containing a newline are outside this line protocol
tr '\0' '\n' <"$git_nul_file" >"$scratch_file"

command -v shellcheck >/dev/null 2>&1 || exit 0

set --
while IFS= read -r rel_path; do
	[ -n "$rel_path" ] || continue
	abs_path="$repo_root/$rel_path"
	[ -f "$abs_path" ] || continue
	case "$rel_path" in
	*.sh | *.bash | *.bats)
		set -- "$@" "$abs_path"
		continue
		;;
	*.*) continue ;;
	esac
	# [[:space:]] rather than a literal space: a CRLF shebang line ends with a carriage return
	head -n1 "$abs_path" 2>/dev/null |
		grep -qE '^#!.*[/ ](bash|sh|dash|ksh|ash)([[:space:]]|$)' && set -- "$@" "$abs_path"
done <"$scratch_file"
[ "$#" -gt 0 ] || exit 0

# no --severity: it empties the comment list and exits 0, looking like a clean run
shellcheck_json="$(shellcheck --format=json1 --exclude=SC1091 -- "$@" 2>/dev/null)"
shellcheck_exit=$?

if [ "$shellcheck_exit" -ge 2 ]; then
	block_with_reason "devops-lsp shell gate: shellcheck exited ${shellcheck_exit}, which means it did not scan the files (2 = file unreadable, 3 = bad invocation, 4 = bad options). Treat this as unverified, not clean."
	exit 0
fi
[ -n "$shellcheck_json" ] || exit 0

blocking="$(printf '%s' "$shellcheck_json" | jq -r '
  (.comments // [])[]
  | select(.level == "error" or .level == "warning" or .level == "info")
  | "\(.file):\(.line):\(.column): \(.level) SC\(.code) \(.message | gsub("[\\n\\r]+"; " "))
' 2>/dev/null | awk '!seen[$0]++' || true)"

style_count="$(printf '%s' "$shellcheck_json" | jq -r '[(.comments // [])[] | select(.level == "style")] | length' 2>/dev/null || echo 0)"

[ -n "$blocking" ] || exit 0

finding_total="$(printf '%s\n' "$blocking" | wc -l | tr -d ' ')"
shown_findings="$(printf '%s\n' "$blocking" | head -n 40)"
[ "$finding_total" -gt 40 ] && shown_findings="${shown_findings}${newline}... $((finding_total - 40)) more"

reason="devops-lsp shell gate: shellcheck reported ${finding_total} finding(s) at error, warning or info. Fix them before finishing:${newline}${shown_findings}"
[ "${style_count:-0}" -gt 0 ] && reason="${reason}${newline}${newline}There are also ${style_count} style-level suggestion(s), which do not block."

block_with_reason "$reason"
exit 0
