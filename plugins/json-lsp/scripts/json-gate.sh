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

set --
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	[ -f "$root/$rel" ] || continue
	case "$rel" in
	*.json | *.jsonc) set -- "$@" "$rel" ;;
	esac
done <"$list"
[ "$#" -gt 0 ] || exit 0

bin() {
	if [ -x "$root/node_modules/.bin/$1" ]; then
		printf '%s' "$root/node_modules/.bin/$1"
	elif command -v "$1" >/dev/null 2>&1; then
		command -v "$1"
	fi
}

p="$(bin prettier)"
[ -n "$p" ] || exit 0

if out="$(cd "$root" && "$p" --check -- "$@" 2>&1)"; then
	exit 0
fi

reason="devops-lsp JSON gate: 'prettier --check' found unformatted or unparseable JSON. Fix it before finishing:${nl}${out}"
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
