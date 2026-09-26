#!/bin/sh
set -u

nl='
'

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

list="$(mktemp)"
trap 'rm -f "$list"' EXIT
(cd "$root" && {
	git diff --name-only -z
	git diff --name-only --cached -z
	git ls-files --others --exclude-standard -z
} 2>/dev/null) | tr '\0' '\n' >"$list"

command -v shellcheck >/dev/null 2>&1 || exit 0

set --
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	abs="$root/$rel"
	[ -f "$abs" ] || continue
	case "$rel" in
	*.sh | *.bash | *.bats)
		set -- "$@" "$abs"
		continue
		;;
	*.*) continue ;;
	esac
	head -n1 "$abs" 2>/dev/null |
		grep -qE '^#!.*[/ ](bash|sh|dash|ksh|ash)([ ]|$)' && set -- "$@" "$abs"
done <"$list"
[ "$#" -gt 0 ] || exit 0

# no --severity: it empties the comment list and exits 0, looking like a clean run
out="$(shellcheck --format=json1 --exclude=SC1091 "$@" 2>/dev/null)"
rc=$?

if [ "$rc" -ge 2 ]; then
	reason="devops-lsp shell gate: shellcheck exited ${rc}, which means it did not scan the files (2 = file unreadable, 3 = bad invocation, 4 = bad options). Treat this as unverified, not clean."
	jq -n --arg r "$reason" '{decision: "block", reason: $r}'
	exit 0
fi
[ -n "$out" ] || exit 0

blocking="$(printf '%s' "$out" | jq -r '
  (.comments // [])[]
  | select(.level == "error" or .level == "warning" or .level == "info")
  | "\(.file):\(.line):\(.column): \(.level) SC\(.code) \(.message)"
' 2>/dev/null | awk '!seen[$0]++' || true)"

stylecount="$(printf '%s' "$out" | jq -r '[(.comments // [])[] | select(.level == "style")] | length' 2>/dev/null || echo 0)"

[ -n "$blocking" ] || exit 0

total="$(printf '%s\n' "$blocking" | wc -l | tr -d ' ')"
shown="$(printf '%s\n' "$blocking" | head -40)"
[ "$total" -gt 40 ] && shown="${shown}${nl}... $((total - 40)) more"

reason="devops-lsp shell gate: shellcheck reported ${total} finding(s) at error, warning or info. Fix them before finishing:${nl}${shown}"
[ "${stylecount:-0}" -gt 0 ] && reason="${reason}${nl}${nl}There are also ${stylecount} style-level suggestion(s), which do not block."

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
