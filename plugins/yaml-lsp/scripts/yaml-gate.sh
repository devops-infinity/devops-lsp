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
	*.yaml | *.yml) set -- "$@" "$rel" ;;
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

problems=""

default_conf='{
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
if command -v yamllint >/dev/null 2>&1; then
	cfg=""
	for c in .yamllint .yamllint.yaml .yamllint.yml; do
		if [ -f "$root/$c" ]; then
			cfg="$root/$c"
			break
		fi
	done
	if [ -n "$cfg" ]; then
		y="$(cd "$root" && yamllint -c "$cfg" -- "$@" 2>&1)"
	else
		y="$(cd "$root" && yamllint -d "$default_conf" -- "$@" 2>&1)"
	fi
	yrc=$?
	# yamllint above 1 is a usage or I/O failure, so an empty result would read as clean
	if [ "$yrc" -ge 2 ]; then
		problems="${problems}yamllint exited ${yrc}, so the lint did not run. Treat this as unverified, not clean.${nl}"
	elif [ -n "$y" ]; then
		problems="${problems}${y}${nl}"
	fi
fi

p="$(bin prettier)"
if [ -n "$p" ]; then
	if ! out="$(cd "$root" && "$p" --check -- "$@" 2>&1)"; then
		problems="${problems}${out}${nl}"
	fi
fi

[ -n "$problems" ] || exit 0

reason="devops-lsp YAML gate: yamllint or 'prettier --check' reported problems. Fix them before finishing:${nl}${problems}"
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
