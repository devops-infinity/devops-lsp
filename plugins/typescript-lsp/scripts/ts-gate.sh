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
[ -f "$root/tsconfig.json" ] || exit 0

list="$(mktemp)"
trap 'rm -f "$list"' EXIT
(cd "$root" && {
	git diff --name-only -z
	git diff --name-only --cached -z
	git ls-files --others --exclude-standard -z
} 2>/dev/null) | tr '\0' '\n' >"$list"

changed=""
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	[ -f "$root/$rel" ] || continue
	case "$rel" in
	*.ts | *.tsx | *.mts | *.cts | *.js | *.jsx | *.mjs | *.cjs) changed="${changed}${rel}${nl}" ;;
	esac
done <"$list"
[ -n "$changed" ] || exit 0

# an unresolvable tsc writes nothing, and grepping that reports the project clean
if ! (cd "$root" && npx --no-install tsc --version >/dev/null 2>&1); then
	reason="devops-lsp type-check gate: 'npx --no-install tsc' could not run, so the type check did not happen. Install typescript in this project. Treat this as unverified, not clean."
	jq -n --arg r "$reason" '{decision: "block", reason: $r}'
	exit 0
fi

out="$(cd "$root" && npx --no-install tsc --noEmit -p tsconfig.json 2>&1 || true)"
printf '%s' "$out" | grep -qE 'error TS' || exit 0

reason="devops-lsp type-check gate: 'tsc --noEmit' reported errors. Fix them before finishing:${nl}${out}"
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
