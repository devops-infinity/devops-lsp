#!/bin/sh
set -u

nl='
'

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file" in
*.sh | *.bash | *.bats) ;;
*) exit 0 ;;
esac
[ -f "$file" ] || exit 0

dir="$(cd "$(dirname -- "$file")" 2>/dev/null && pwd)" || exit 0
base="$(basename -- "$file")"

apply_note=""

if command -v shellcheck >/dev/null 2>&1; then
	diff_out="$(cd "$dir" && shellcheck --format=diff "$base" 2>/dev/null || true)"
	if [ -n "$diff_out" ]; then
		if ! printf '%s\n' "$diff_out" | (cd "$dir" && git apply - 2>/dev/null); then
			if ! printf '%s\n' "$diff_out" | (cd "$dir" && patch -p1 -s >/dev/null 2>&1); then
				rm -f "$dir/$base.orig" "$dir/$base.rej" 2>/dev/null || true
				apply_note="shellcheck produced a fix for ${file}, but neither 'git apply' nor 'patch' could apply it. The fix did not land."
			fi
		fi
	fi
fi

case "$base" in
*.bats) ;;
*)
	if command -v shfmt >/dev/null 2>&1; then
		# any shfmt flag discards .editorconfig, losing the repo's own declared style
		err="$(shfmt --write "$file" 2>&1)"
		rc=$?
		if [ "$rc" -ne 0 ]; then
			ctx="devops-lsp auto-heal ran 'shfmt --write' on ${file} and it failed to parse. Fix the syntax:${nl}${err}"
			jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
			exit 0
		fi
	fi
	;;
esac

left=""
if command -v shellcheck >/dev/null 2>&1; then
	left="$(cd "$dir" && shellcheck --format=json1 --exclude=SC1091 "$base" 2>/dev/null |
		jq -r '(.comments // [])[] | select(.level != "style") | "\(.file):\(.line):\(.column): \(.level) SC\(.code) \(.message)"' 2>/dev/null || true)"
fi

[ -n "$left" ] || [ -n "$apply_note" ] || exit 0

ctx="devops-lsp auto-heal fixed and formatted ${file}."
[ -n "$apply_note" ] && ctx="$ctx${nl}${apply_note}"
[ -n "$left" ] && ctx="$ctx${nl}shellcheck still reports the following; address it:${nl}${left}"
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
