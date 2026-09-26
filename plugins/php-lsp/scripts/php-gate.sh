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
errfile="$(mktemp)"
trap 'rm -f "$list" "$errfile"' EXIT
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
	*.php | *.phtml)
		case "$rel" in
		*.blade.php) continue ;;
		esac
		changed="${changed}${rel}${nl}"
		;;
	esac
done <"$list"
[ -n "$changed" ] || exit 0

printf '%s' "$changed" >"$list"
projects="$(while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	dir="$root/$(dirname -- "$rel")"
	[ -d "$dir" ] || continue
	probe="$(cd "$dir" && pwd)"
	while [ -n "$probe" ] && [ "$probe" != "/" ]; do
		if [ -f "$probe/composer.json" ]; then
			printf '%s\n' "$probe"
			break
		fi
		probe="$(dirname -- "$probe")"
	done
done <"$list" | sort -u)"
[ -n "$projects" ] || exit 0

errors=""
broken=""
printf '%s' "$projects" >"$list"
while IFS= read -r proj; do
	[ -n "$proj" ] || continue

	phpstan=""
	if [ -x "$proj/vendor/bin/phpstan" ]; then
		phpstan="$proj/vendor/bin/phpstan"
	elif command -v phpstan >/dev/null 2>&1; then
		phpstan="$(command -v phpstan)"
	fi
	[ -n "$phpstan" ] || continue

	level_note=""
	if [ -f "$proj/phpstan.neon" ] || [ -f "$proj/phpstan.neon.dist" ] || [ -f "$proj/phpstan.dist.neon" ]; then
		out="$(cd "$proj" && "$phpstan" analyse --error-format=json --no-progress --no-interaction --memory-limit=2G 2>"$errfile")"
	else
		out="$(cd "$proj" && "$phpstan" analyse --level=5 --error-format=json --no-progress --no-interaction --memory-limit=2G . 2>"$errfile")"
		level_note=" (no phpstan.neon found, ran at level 5)"
	fi
	rc=$?
	err="$(cat "$errfile" 2>/dev/null || true)"
	: >"$errfile"

	# PHPStan exits 1 for findings and for a setup failure alike, so the JSON decides
	if ! printf '%s' "$out" | jq -e 'has("totals")' >/dev/null 2>&1; then
		broken="${broken}- ${proj}: PHPStan exited ${rc} without a usable report${nl}"
		[ -n "$err" ] && broken="${broken}  $(printf '%s' "$err" | head -n1)${nl}"
		continue
	fi

	found="$(printf '%s' "$out" | jq -r '
    (.files // {}) | to_entries[]
    | .key as $f
    | (.value.messages // [])[]
    | "\($f):\(.line // 0): \(.message)"
  ' 2>/dev/null || true)"
	general="$(printf '%s' "$out" | jq -r '(.errors // [])[]' 2>/dev/null || true)"

	[ -n "$found" ] && errors="${errors}${found}${level_note}${nl}"
	[ -n "$general" ] && errors="${errors}${general}${nl}"
done <"$list"

errors="$(printf '%s' "$errors" | grep -v '^$' | awk '!seen[$0]++' || true)"

if [ -z "$errors" ] && [ -z "$broken" ]; then
	exit 0
fi

reason="devops-lsp PHP gate:"
if [ -n "$broken" ]; then
	reason="${reason}${nl}The check did not complete for some projects. Treat these as unverified, not clean:${nl}${broken}"
fi
if [ -n "$errors" ]; then
	total="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
	shown="$(printf '%s\n' "$errors" | head -40)"
	[ "$total" -gt 40 ] && shown="${shown}${nl}... $((total - 40)) more"
	reason="${reason}${nl}PHPStan reported ${total} error(s). Fix them before finishing:${nl}${shown}"
fi

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
