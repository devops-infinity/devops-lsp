#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

changed="$(cd "$root" && git status --porcelain 2>/dev/null |
	sed -E 's/^.{3}//; s/^.* -> //; s/^"(.*)"$/\1/' || true)"
[ -n "$changed" ] || exit 0

command -v shellcheck >/dev/null 2>&1 || exit 0

# Match by extension, then by shebang. Plenty of real shell lives in extensionless
# files - git hooks, CLI entry points - and skipping those would be a silent gap.
files=""
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	abs="$root/$rel"
	[ -f "$abs" ] || continue
	case "$rel" in
	*.sh | *.bash | *.bats)
		files="$files$abs"$'\n'
		continue
		;;
	*.*) continue ;;
	esac
	head -n1 "$abs" 2>/dev/null |
		grep -qE '^#!.*\b(bash|sh|dash|ksh|ash)\b' && files="$files$abs"$'\n'
done <<EOF
$changed
EOF
[ -n "$files" ] || exit 0

# Deliberately no --severity filter: it makes shellcheck emit an empty comment list
# AND exit 0, so a filtered run is indistinguishable from a clean one. Severity is
# filtered below instead, where an empty result still means something.
out="$(printf '%s' "$files" | grep -v '^$' | tr '\n' '\0' |
	xargs -0 shellcheck --format=json1 --exclude=SC1091 2>/dev/null)"
status=$?

# 0 clean, 1 issues found. 2 = a file could not be processed, 3 = bad invocation,
# 4 = bad options. On those the scan never happened, and reporting "no findings"
# would be a lie, so they block with their own message.
if [ "$status" -ge 2 ]; then
	reason="devops-lsp shell gate: shellcheck exited ${status}, which means it did not scan the files (2 = file unreadable, 3 = bad invocation, 4 = bad options). Treat this as unverified, not clean."
	jq -n --arg r "$reason" '{decision: "block", reason: $r}'
	exit 0
fi
[ -n "$out" ] || exit 0

# Block on error, warning and info. Only style is advisory. The destructive defects
# sit at warning (SC2115 `rm -rf $x/`, SC2164 a cd that failed and kept going) and
# the single most common shell bug, SC2086 unquoted expansion, sits at info - an
# error-only threshold ships all three.
blocking="$(printf '%s' "$out" | jq -r '
  (.comments // [])[]
  | select(.level == "error" or .level == "warning" or .level == "info")
  | "\(.file):\(.line):\(.column): \(.level) SC\(.code) \(.message)"
' 2>/dev/null | awk '!seen[$0]++' || true)"

stylecount="$(printf '%s' "$out" | jq -r '[(.comments // [])[] | select(.level == "style")] | length' 2>/dev/null || echo 0)"

[ -n "$blocking" ] || exit 0

total="$(printf '%s\n' "$blocking" | wc -l | tr -d ' ')"
shown="$(printf '%s\n' "$blocking" | head -40)"
[ "$total" -gt 40 ] && shown="$shown"$'\n'"... $((total - 40)) more"

reason="devops-lsp shell gate: shellcheck reported ${total} finding(s) at error, warning or info. Fix them before finishing:"$'\n'"$shown"
[ "${stylecount:-0}" -gt 0 ] && reason="$reason"$'\n\n'"There are also ${stylecount} style-level suggestion(s), which do not block."

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
